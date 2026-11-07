import Foundation
import CoreGraphics
import Testing
@testable import GuidesCore

private let layoutDisplay = DisplayConfiguration(id: 7, size: CGSize(width: 800, height: 600), backingFactor: 2)

private func layoutSession() throws -> DisplaySession {
    var session = DisplaySession(size: layoutDisplay.size, rootPixels: 20)
    let before = session.document
    session.document.add(axis: .horizontal, position: 42.5)
    session.document.add(axis: .vertical, position: 128)
    session.document.setArea(CGRect(x: 120, y: 80, width: 240, height: 160))
    session.history.record(before: before, after: session.document)
    session.calibration.setScale(percent: 125)
    session.unit = .rem
    session.grid = try GridConfiguration(isEnabled: true, spacing: 16, unit: .designPixels, origin: CGPoint(x: 12, y: 8), opacity: 0.4)
    for (index, tool) in [AnnotationTool.rectangle, .line, .arrow].enumerated() {
        session.annotations.setTool(tool)
        session.annotations.setColor(index == 0 ? .transparent : .cyan)
        session.annotations.begin(at: CGPoint(x: 30, y: 30 + index * 50))
        session.annotations.drag(to: CGPoint(x: 300, y: 160 + index * 50))
        session.annotations.end()
    }
    session.annotations.setTool(.rectangle)
    session.annotations.apply(style: AnnotationStyle(color: .orange, stroke: .thick), spotlight: false, dimOpacity: 0.7)
    return session
}

@Test func layoutRoundTripPreservesAllContentButStartsFreshCalibrationAndHistory() throws {
    let source = try layoutSession()
    let content = try SavedLayoutContent(session: source, backingFactor: 2)
    let decoded = try JSONDecoder().decode(SavedLayoutContent.self, from: JSONEncoder().encode(content))
    let restored = try decoded.restoredSession(rootPixels: 24)
    #expect(try SavedLayoutContent(session: restored, backingFactor: 2) == content)
    #expect(restored.document.area?.rect == source.document.area?.rect)
    #expect(restored.annotations.document.spotlight == source.annotations.document.spotlight)
    #expect(restored.annotations.document.shapes[0].style.color == .transparent)
    #expect(restored.annotations.style == source.annotations.style && !restored.annotations.newRectanglesSpotlight)
    #expect(restored.annotations.document.dimOpacity == 0.7)
    #expect(restored.document.selection.isEmpty && !restored.document.isAreaSelected)
    #expect(restored.annotations.document.selectedID == nil)
    #expect(!restored.history.canUndo && !restored.annotations.canUndo)
    #expect(!restored.calibration.isConfirmed && restored.calibration.rootPixels == 24 && restored.unit == .screenPoints)
    #expect(throws: GridError.calibration) { try GridGeometry(configuration: restored.grid, size: layoutDisplay.size, calibration: restored.calibration, backingFactor: 2) }
}

@Test func savedLayoutsRequireExactDimensionsAndBackingButNotDisplayIdentity() throws {
    let content = try SavedLayoutContent(session: layoutSession(), backingFactor: 2)
    #expect(content.isCompatible(with: DisplayConfiguration(id: 99, size: layoutDisplay.size, backingFactor: 2)))
    #expect(!content.isCompatible(with: DisplayConfiguration(id: 7, size: layoutDisplay.size, backingFactor: 1)))
    #expect(!content.isCompatible(with: DisplayConfiguration(id: 7, size: CGSize(width: 800.5, height: 600), backingFactor: 2)))
}

private func alteredContent(_ mutate: (inout [String: Any]) -> Void) throws -> SavedLayoutContent {
    let original = try SavedLayoutContent(session: layoutSession(), backingFactor: 2)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    mutate(&json)
    return try JSONDecoder().decode(SavedLayoutContent.self, from: JSONSerialization.data(withJSONObject: json))
}

@Test func layoutsRejectCorruptGeometryStylesAndSpotlightRatherThanClamp() throws {
    let mutations: [(inout [String: Any]) -> Void] = [
        { $0["backingFactor"] = 0 }, { $0["dimOpacity"] = 0.9 }, { $0["spotlightIndex"] = 100 },
        { $0["spotlightIndex"] = 1 }, { $0["size"] = [0, 600] },
        { $0["guides"] = [["axis": "horizontal", "position": 601]] },
        { $0["guides"] = [["axis": "diagonal", "position": 10]] },
        { $0["style"] = ["color": "Unknown", "stroke": 4] },
        { $0["style"] = ["color": "Pink", "stroke": 99] },
        { $0["area"] = [[120, 80], [-1, 100]] },
        { $0["area"] = [[120, 80], [900, 100]] },
        { $0["grid"] = ["enabled": true, "spacing": 8, "unit": "Screen pt", "origin": [801, 0], "opacity": 0.4] },
        { $0["shapes"] = [["kind": "Line", "start": [0, 0], "end": [0, 0], "style": ["color": "Pink", "stroke": 4]]] }
    ]
    for mutate in mutations {
        #expect(throws: (any Error).self) { _ = try alteredContent(mutate).restoredSession(rootPixels: 16) }
    }
    var many = DisplaySession(size: layoutDisplay.size, rootPixels: 16)
    for _ in 0...1000 { many.document.add(axis: .horizontal, position: 10) }
    #expect(throws: LayoutError.self) { try SavedLayoutContent(session: many, backingFactor: 2) }
}

@Test func layoutLoadAndRecoveryAreAtomicAndPreserveHistoryAndCurrentRootPreference() throws {
    var current = try layoutSession()
    let original = current
    let empty = try SavedLayoutContent(session: DisplaySession(size: layoutDisplay.size, rootPixels: 16), backingFactor: 2)
    var recovery = LayoutLoadRecovery()
    let wrong = DisplayConfiguration(id: 7, size: layoutDisplay.size, backingFactor: 1)
    #expect(throws: LayoutError.self) { try recovery.load(empty, into: &current, on: wrong) }
    #expect(current.document == original.document && !recovery.canUndo(on: layoutDisplay))
    try recovery.load(empty, into: &current, on: layoutDisplay)
    #expect(current.document.guides.isEmpty && !current.history.canUndo && !current.calibration.isConfirmed)
    #expect(recovery.canUndo(on: layoutDisplay))
    let corrupt = try alteredContent { $0["spotlightIndex"] = -1 }
    #expect(throws: LayoutError.self) { try recovery.load(corrupt, into: &current, on: layoutDisplay) }
    #expect(current.document.guides.isEmpty && recovery.canUndo(on: layoutDisplay))
    current.calibration.setRootPixels(32)
    #expect(throws: LayoutError.self) { try recovery.undo(into: &current, on: wrong) }
    try recovery.undo(into: &current, on: layoutDisplay)
    #expect(current.document == original.document && current.annotations.document == original.annotations.document)
    #expect(current.history.canUndo && current.annotations.canUndo)
    #expect(current.calibration.isConfirmed && current.calibration.pointsPerPixel == original.calibration.pointsPerPixel)
    #expect(current.calibration.rootPixels == 32 && current.unit == .rem)
    #expect(!recovery.canUndo(on: layoutDisplay))
    #expect(current.history.undo(current: current.document)?.guides.isEmpty == true)
    try recovery.load(empty, into: &current, on: layoutDisplay)
    recovery.invalidate([99]); #expect(recovery.canUndo(on: layoutDisplay))
    recovery.invalidate([7]); #expect(!recovery.canUndo(on: layoutDisplay))
}

private func layoutReference() throws -> ReferenceOverlay {
    let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = InspectedImage(metadata: ImageMetadata(name: "layout-test.png", isClipboardData: false,
        encodedWidth: 2, encodedHeight: 2, orientation: 1, typeIdentifier: "public.png", byteCount: 16,
        hasAlpha: true, imageCount: 1, primaryImageIndex: 0), preview: try #require(context.makeImage()))
    return try ReferenceOverlay(image: image, displaySize: layoutDisplay.size)
}

@Test func layoutLoadingAndRecoveryKeepTheCurrentReference() throws {
    var current = try layoutSession()
    current.reference = try layoutReference()
    let content = try SavedLayoutContent(session: current, backingFactor: 2)
    var recovery = LayoutLoadRecovery()
    try recovery.load(content, into: &current, on: layoutDisplay)
    #expect(current.reference?.image.metadata.name == "layout-test.png")
    current.reference = nil
    try recovery.undo(into: &current, on: layoutDisplay)
    #expect(current.reference == nil)
}

@Test func layoutRecoveryDoesNotRetainRemovedOrReplacedReferenceImages() throws {
    var current = try layoutSession()
    current.reference = try layoutReference()
    weak var originalPreview = current.reference?.image.preview
    let content = try SavedLayoutContent(session: current, backingFactor: 2)
    var recovery = LayoutLoadRecovery()
    try recovery.load(content, into: &current, on: layoutDisplay)
    #expect(originalPreview != nil)
    current.reference = try layoutReference()
    #expect(originalPreview == nil)
    weak var replacementPreview = current.reference?.image.preview
    current.reference = nil
    #expect(replacementPreview == nil && recovery.canUndo(on: layoutDisplay))
    try recovery.undo(into: &current, on: layoutDisplay)
    #expect(current.reference == nil)
}

private func temporaryLibrary() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("guides-layout-test-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("layouts.json")
}

@Test @MainActor func layoutLibrarySavesRenamesDeletesAndRecoversAcrossFreshStores() throws {
    let url = try temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = SavedLayoutsStore(fileURL: url)
    #expect(store.storageError == nil && store.layouts.isEmpty)
    let content = try SavedLayoutContent(session: layoutSession(), backingFactor: 2)
    let id = try store.save(name: "  Desktop  ", content: content)
    #expect(store.layouts[0].name == "Desktop")
    let second = try store.save(name: "Tablet", content: content)
    try store.rename(id, to: "DESKTOP")
    #expect(store.layouts[0].id == id && store.layouts[0].content == content)
    #expect(throws: LayoutError.self) { try store.rename(second, to: "desktop") }
    let bytes = try Data(contentsOf: url)
    for badName in [" ", "A\nB", "A\u{7}B", String(repeating: "x", count: 81), "desktop"] {
        #expect(throws: LayoutError.self) { try store.save(name: badName, content: content) }
        #expect(try Data(contentsOf: url) == bytes)
    }
    try store.delete(id)
    #expect(store.layouts.map(\.id) == [second] && store.canUndoDelete)
    #expect(try store.undoDelete() == id)
    #expect(store.layouts.map(\.id) == [id, second] && !store.canUndoDelete)
    let relaunched = SavedLayoutsStore(fileURL: url)
    #expect(relaunched.layouts == store.layouts && !relaunched.canUndoDelete)
    try store.delete(id)
    _ = try store.save(name: "desktop", content: content)
    #expect(throws: LayoutError.self) { try store.undoDelete() }
    #expect(store.canUndoDelete)
}

@Test @MainActor func unreadableCorruptFutureAndOversizedLibrariesAreRetainedAndBlockWrites() throws {
    let url = try temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let content = try SavedLayoutContent(session: layoutSession(), backingFactor: 2)
    for bytes in [Data("corrupt".utf8), Data("{\"version\":3,\"layouts\":[]}".utf8), Data(repeating: 32, count: SavedLayoutsStore.maximumBytes + 1)] {
        try bytes.write(to: url)
        let store = SavedLayoutsStore(fileURL: url)
        #expect(store.storageError != nil && store.layouts.isEmpty)
        #expect(throws: LayoutError.self) { try store.save(name: "Do not overwrite", content: content) }
        #expect(try Data(contentsOf: url) == bytes)
        try FileManager.default.removeItem(at: url)
        store.reload()
        #expect(store.storageError == nil)
        _ = try store.save(name: "Retry works", content: content)
    }
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    #expect(SavedLayoutsStore(fileURL: url).storageError != nil)
}

@Test @MainActor func invalidArchiveContentsFailAsAWhole() throws {
    let url = try temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let good = SavedLayout(id: UUID(), name: "One", content: try SavedLayoutContent(session: layoutSession(), backingFactor: 2))
    let invalid = SavedLayout(id: UUID(), name: "Two", content: try alteredContent { $0["dimOpacity"] = -1 })
    let duplicateName = SavedLayout(id: UUID(), name: "ONE", content: good.content)
    for items in [[good, invalid], [good, good], [good, duplicateName], (0...100).map { SavedLayout(id: UUID(), name: "Layout \($0)", content: good.content) }] {
        let bytes = try JSONEncoder().encode(SavedLayoutsStore.Archive(version: 1, layouts: items))
        try bytes.write(to: url)
        let store = SavedLayoutsStore(fileURL: url)
        #expect(store.storageError != nil && store.layouts.isEmpty)
        #expect(try Data(contentsOf: url) == bytes)
    }
}

@Test @MainActor func failedWritesLeaveLibraryAndDeleteRecoveryUnchanged() throws {
    let url = try temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = SavedLayoutsStore(fileURL: url)
    let id = try store.save(name: "Keep", content: SavedLayoutContent(session: layoutSession(), backingFactor: 2))
    let original = store.layouts
    // A directory at the destination reliably fails even when the test process can bypass file permissions.
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    #expect(throws: (any Error).self) { try store.rename(id, to: "Failed") }
    #expect(throws: (any Error).self) { try store.delete(id) }
    #expect(store.layouts == original && !store.canUndoDelete)
    try FileManager.default.removeItem(at: url)
    try store.delete(id)
    #expect(store.layouts.isEmpty && store.canUndoDelete)
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    #expect(throws: (any Error).self) { try store.undoDelete() }
    #expect(store.layouts.isEmpty && store.canUndoDelete)
}
