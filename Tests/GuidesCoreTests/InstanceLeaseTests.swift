import Foundation
import Testing
@testable import GuidesCore

@Test func instanceLeaseRejectsContentionAndRecoversWithoutDeletingFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("instance.lock")
    var first: InstanceLease? = try #require(try InstanceLease(at: url))
    withExtendedLifetime(first) {
        #expect(throws: Never.self) {
            let second = try InstanceLease(at: url)
            #expect(second == nil)
        }
    }
    first = nil
    #expect(FileManager.default.fileExists(atPath: url.path))
    let recovered = try #require(try InstanceLease(at: url))
    withExtendedLifetime(recovered) { #expect(FileManager.default.fileExists(atPath: url.path)) }
}

@Test func instanceLeaseRejectsSymlinksAndMissingDirectories() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = directory.appendingPathComponent("original")
    try Data("retain".utf8).write(to: original)
    let link = directory.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
    #expect(throws: (any Error).self) { try InstanceLease(at: link) }
    #expect(try String(contentsOf: original, encoding: .utf8) == "retain")
    #expect(throws: (any Error).self) { try InstanceLease(at: directory.appendingPathComponent("missing/lock")) }
}
