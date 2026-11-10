import AppKit
import CoreFoundation
import GuidesCore

private struct CommandRequest: Codable {
    let version: Int
    let arguments: [String]
}

/// Per-login-user Mach messaging, with no socket, network listener, arbitrary dispatch or file access.
@MainActor
final class CommandChannel {
    static var name: CFString { "dev.guides.local.commands.v1.\(getuid())" as CFString }
    private var port: CFMessagePort?
    private var source: CFRunLoopSource?
    private let handle: (GuidesCommand) throws -> [String: Any]

    init(handle: @escaping (GuidesCommand) throws -> [String: Any]) {
        self.handle = handle
        var context = CFMessagePortContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        port = CFMessagePortCreateLocal(nil, Self.name, { _, messageID, data, info in
            // The source is installed only on the main run loop.
            guard let info else { return nil }
            let reply = MainActor.assumeIsolated {
                let channel = Unmanaged<CommandChannel>.fromOpaque(info).takeUnretainedValue()
                return channel.receive(messageID: messageID, data: data)
            }
            return Unmanaged.passRetained(reply as CFData)
        }, &context, nil)
        if let port {
            source = CFMessagePortCreateRunLoopSource(nil, port, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        } else { NSLog("Guides CLI unavailable: another instance may own the command port.") }
    }

    private func receive(messageID: Int32, data: CFData?) -> Data {
        do {
            guard messageID == 1, let data, CFDataGetLength(data) <= 8192 else { throw CommandLineError("Invalid or oversized request.") }
            let request = try JSONDecoder().decode(CommandRequest.self, from: data as Data)
            guard request.version == 1 else { throw CommandLineError("Unsupported command protocol.") }
            var response = try handle(GuidesCommand.parse(request.arguments))
            response["ok"] = true
            return try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
        } catch { return Self.errorData(error.localizedDescription) }
    }

    static func errorData(_ message: String) -> Data {
        // The dictionary contains only JSON-compatible scalar values.
        try! JSONSerialization.data(withJSONObject: ["ok": false, "error": message], options: [.sortedKeys])
    }

    static func runClient(arguments: [String]) -> Int32 {
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
            print(GuidesCommand.help); return 0
        }
        if arguments.first == "launch" {
            guard arguments == ["launch"] else { write(errorData("launch accepts no arguments.")); return 2 }
            do {
                write(try JSONSerialization.data(withJSONObject: SingleInstance.launch(), options: [.sortedKeys]))
                return 0
            } catch { write(errorData(error.localizedDescription)); return 1 }
        }
        do {
            _ = try GuidesCommand.parse(arguments)
        } catch {
            write(Self.errorData(error.localizedDescription)); return 2
        }
        do {
            let data = try request(arguments)
            write(data)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return object?["ok"] as? Bool == true ? 0 : 1
        } catch {
            write(errorData(error.localizedDescription)); return 1
        }
    }

    static func isReady(processIdentifier: pid_t) -> Bool {
        guard let data = try? request(["status"], sendTimeout: 0.1, receiveTimeout: 0.2),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["ok"] as? Bool == true, let state = object["state"] as? [String: Any],
              let pid = state["pid"] as? NSNumber else { return false }
        return pid.int32Value == processIdentifier
    }

    private static func request(_ arguments: [String], sendTimeout: CFTimeInterval = 2,
                                receiveTimeout: CFTimeInterval = 3) throws -> Data {
        guard let remote = CFMessagePortCreateRemote(nil, name) else {
            throw CommandLineError("Open the CLI-enabled build of Guides first. Try guides launch; quit older builds only after saving any work. If it is already running, the execution sandbox may block local Mach IPC; use the execution tool's normal approval path.")
        }
        let encoded = try JSONEncoder().encode(CommandRequest(version: 1, arguments: arguments))
        var reply: Unmanaged<CFData>?
        let result = CFMessagePortSendRequest(remote, 1, encoded as CFData, sendTimeout, receiveTimeout,
            CFRunLoopMode.defaultMode.rawValue, &reply)
        let received = reply?.takeRetainedValue() as Data?
        guard result == kCFMessagePortSuccess, let data = received, data.count <= 1_048_576 else {
            throw CommandLineError("Command transport failed (\(result)); execution may be uncertain. Check status before retrying a mutation.")
        }
        return data
    }

    private static func write(_ data: Data) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}
