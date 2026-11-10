import Darwin
import Foundation

/// The kernel owns exclusivity; the file remains in place so all launches lock the same inode.
public final class InstanceLease {
    private let descriptor: Int32

    /// Returns nil only when another process holds the lease. All other failures stop startup.
    public init?(at url: URL) throws {
        let descriptor = url.path.withCString { Darwin.open($0, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600)) }
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_uid == geteuid(),
              metadata.st_mode & S_IFMT == S_IFREG else {
            Darwin.close(descriptor)
            throw POSIXError(.EPERM)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            Darwin.close(descriptor)
            if failure == EWOULDBLOCK || failure == EAGAIN { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        self.descriptor = descriptor
    }

    deinit { Darwin.close(descriptor) }
}
