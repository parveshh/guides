import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GuidesCore

private func imageFixture(type: UTType = .png, width: Int = 120, height: Int = 80,
                          alpha: Bool = true, orientation: Int = 1, count: Int = 1) throws -> Data {
    let info = alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: alpha ? 0.5 : 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, count, nil))
    let properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation,
        kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144]
    for _ in 0..<count { CGImageDestinationAddImage(destination, image, properties as CFDictionary) }
    try #require(CGImageDestinationFinalize(destination))
    return data as Data
}

@Test func imagePixelsIgnoreDPIAndScreenScale() throws {
    let data = try imageFixture()
    let result = try ImageInspection.inspect(data: data, name: "asset.png")
    let metadata = result.metadata
    #expect(metadata.width == 120 && metadata.height == 80)
    #expect(metadata.dimensions == "120 × 80 px")
    #expect(metadata.widthText == "120px" && metadata.heightText == "80px")
    #expect(metadata.aspectRatio == "3:2")
    #expect(metadata.format == "PNG" && metadata.typeIdentifier == UTType.png.identifier)
    #expect(metadata.byteCount == data.count)
    #expect(metadata.hasAlpha == true)
    #expect(metadata.name == "asset.png" && !metadata.isClipboardData)
    #expect(metadata.imageCount == 1 && metadata.primaryImageIndex == 0)
}

@Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8])
func orientedImageDimensionsMatchPreview(orientation: Int) throws {
    let data = try imageFixture(type: .jpeg, alpha: false, orientation: orientation)
    let result = try ImageInspection.inspect(data: data, name: "rotated.jpg")
    let swapsAxes = (5...8).contains(orientation)
    #expect(result.metadata.orientation == orientation)
    #expect(result.metadata.encodedWidth == 120 && result.metadata.encodedHeight == 80)
    #expect(result.metadata.width == (swapsAxes ? 80 : 120))
    #expect(result.metadata.height == (swapsAxes ? 120 : 80))
    #expect(result.metadata.aspectRatio == (swapsAxes ? "2:3" : "3:2"))
    #expect(result.preview.width == result.metadata.width)
    #expect(result.preview.height == result.metadata.height)
    #expect(result.metadata.hasAlpha != true)
}

@Test func previewIsBoundedWithoutChangingOriginalDimensions() throws {
    let result = try ImageInspection.inspect(data: imageFixture(width: 2_400, height: 1_600), name: "large.png")
    #expect(result.metadata.dimensions == "2400 × 1600 px")
    #expect(max(result.preview.width, result.preview.height) == ImageInspection.previewMaximumPixels)
    #expect(result.preview.width > result.preview.height)
}

@Test func clipboardRepresentationAndMultipleImagesAreExplicit() throws {
    let result = try ImageInspection.inspect(data: imageFixture(type: .tiff, count: 2),
        name: "Clipboard image", isClipboardData: true)
    #expect(result.metadata.isClipboardData)
    #expect(result.metadata.format == "TIF" || result.metadata.format == "TIFF")
    #expect(result.metadata.imageCount == 2)
    #expect(result.metadata.primaryImageIndex == 0)
}

@Test func invalidImageDataIsRejected() {
    for data in [Data(), Data("not an image".utf8), Data([0x89, 0x50, 0x4E, 0x47])] {
        #expect(throws: ImageInspectionError.invalidImage) {
            try ImageInspection.inspect(data: data, name: "invalid.png")
        }
    }
}

@Test func fileImportReadsOriginalBytesAndRejectsUnsupportedInputs() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("fixture.png")
    let data = try imageFixture()
    try data.write(to: url)
    let loader = ImageInspectionLoader()
    let result = try await loader.inspect(.file(url))
    #expect(result.metadata.name == "fixture.png" && result.metadata.byteCount == data.count)
    #expect(!result.metadata.isClipboardData)
    await #expect(throws: ImageInspectionError.unreadableFile) { try await loader.inspect(.file(directory)) }
    await #expect(throws: ImageInspectionError.unreadableFile) {
        try await loader.inspect(.file(URL(string: "https://example.com/image.png")!))
    }
    await #expect(throws: ImageInspectionError.unreadableFile) {
        try await loader.inspect(.file(directory.appendingPathComponent("missing.png")))
    }
    // Sparse file tests the preflight without allocating or decoding a 100 MiB bitmap.
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: UInt64(ImageInspection.maximumBytes + 1))
    try handle.close()
    await #expect(throws: ImageInspectionError.tooLarge) { try await loader.inspect(.file(url)) }
}

@Test func cancelledImageImportCannotPublishAResult() async {
    let loader = ImageInspectionLoader()
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await loader.inspect(.clipboard(Data()))
    }
    await #expect(throws: CancellationError.self) { try await task.value }
}

private actor SuspendedImageLoader: ImageInspecting {
    private var pending: CheckedContinuation<InspectedImage, any Error>?
    private var started: CheckedContinuation<Void, Never>?
    func inspect(_ input: ImageInspectionInput) async throws -> InspectedImage {
        try await withCheckedThrowingContinuation {
            pending = $0
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ image: InspectedImage) { pending?.resume(returning: image); pending = nil }
}

@MainActor @Test func rejectedReplacementInvalidatesAnOlderLoad() async throws {
    let image = try ImageInspection.inspect(data: imageFixture(), name: "original.png")
    let loader = SuspendedImageLoader()
    let model = ImageInspectorModel(loader: loader)
    let initial = model.load(.clipboard(Data()))
    await loader.waitUntilStarted()
    await loader.finish(image)
    await initial.value
    #expect(model.image?.metadata.name == "original.png")
    let replacement = model.load(.clipboard(Data()))
    await loader.waitUntilStarted()
    model.rejectImport("Choose one image at a time.")
    #expect(!model.isLoading)
    let other = try ImageInspection.inspect(data: imageFixture(), name: "obsolete.png")
    await loader.finish(other) // An uncooperative decoder can complete after cancellation.
    await replacement.value
    #expect(model.image?.metadata.name == "original.png")
    #expect(model.error == "Choose one image at a time.")
    let closing = model.load(.clipboard(Data()))
    await loader.waitUntilStarted()
    model.clear()
    await loader.finish(other)
    await closing.value
    #expect(model.image == nil && model.error == nil && !model.isLoading)
}

@Test func referencePreviewCanBeLargerButRemainsBounded() throws {
    let data = try imageFixture(width: 4500, height: 40)
    let reference = try ImageInspection.inspect(data: data, name: "wide.png", maximumPreviewPixels: 10000)
    #expect(reference.metadata.width == 4500 && reference.preview.width == 4096)
    let inspector = try ImageInspection.inspect(data: data, name: "wide.png")
    #expect(inspector.preview.width == 800)
}
