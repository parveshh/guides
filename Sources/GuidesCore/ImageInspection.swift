import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageInspectionInput: Sendable {
    case file(URL)
    case clipboard(Data)
}

public enum ImageInspectionError: Error, LocalizedError, Equatable {
    case invalidImage
    case tooLarge
    case unreadableFile

    public var errorDescription: String? {
        switch self {
        case .invalidImage: "This image could not be read. Try a PNG, JPEG, TIFF, GIF, or HEIC image."
        case .tooLarge: "Choose an image no larger than 100 MiB."
        case .unreadableFile: "The file could not be opened. Choose a local image using Open Image."
        }
    }
}

public struct InspectedImage: Sendable {
    public let metadata: ImageMetadata
    public let preview: CGImage
}

public struct ImageMetadata: Sendable {
    public let name: String
    public let isClipboardData: Bool
    public let encodedWidth: Int
    public let encodedHeight: Int
    public let orientation: Int
    public let typeIdentifier: String
    public let byteCount: Int
    public let hasAlpha: Bool?
    public let imageCount: Int
    public let primaryImageIndex: Int

    public var width: Int { (5...8).contains(orientation) ? encodedHeight : encodedWidth }
    public var height: Int { (5...8).contains(orientation) ? encodedWidth : encodedHeight }
    public var dimensions: String { "\(width) × \(height) px" }
    public var widthText: String { "\(width)px" }
    public var heightText: String { "\(height)px" }
    public var format: String {
        UTType(typeIdentifier)?.preferredFilenameExtension?.uppercased() ?? typeIdentifier
    }
    public var aspectRatio: String {
        var a = width, b = height
        while b != 0 { (a, b) = (b, a % b) }
        return "\(width / a):\(height / a)"
    }
    public var alphaDescription: String {
        switch hasAlpha {
        case true: "Present"
        case false: "None"
        case nil: "Unknown"
        }
    }
}

/// Image I/O reads source pixels independently of screen scale, window code, or calibration.
public enum ImageInspection {
    public static let maximumBytes = 100 * 1_024 * 1_024
    public static let previewMaximumPixels = 800

    public static func inspect(data: Data, name: String, isClipboardData: Bool = false) throws -> InspectedImage {
        try Task.checkCancellation()
        guard data.count <= maximumBytes else { throw ImageInspectionError.tooLarge }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, options),
              let type = CGImageSourceGetType(source),
              CGImageSourceGetCount(source) > 0 else { throw ImageInspectionError.invalidImage }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard index < CGImageSourceGetCount(source),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, index, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ImageInspectionError.invalidImage }
        let rawOrientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let orientation = (1...8).contains(rawOrientation) ? rawOrientation : 1
        try Task.checkCancellation()
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: previewMaximumPixels,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let preview = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions as CFDictionary)
        else { throw ImageInspectionError.invalidImage }
        try Task.checkCancellation()
        return InspectedImage(metadata: ImageMetadata(
            name: name, isClipboardData: isClipboardData,
            encodedWidth: width, encodedHeight: height, orientation: orientation,
            typeIdentifier: type as String, byteCount: data.count,
            hasAlpha: properties[kCGImagePropertyHasAlpha] as? Bool,
            imageCount: CGImageSourceGetCount(source), primaryImageIndex: index
        ), preview: preview)
    }
}

/// Serial decoding keeps replacement imports off the UI thread and avoids concurrent large decodes.
public actor ImageInspectionLoader: ImageInspecting {
    public init() {}

    public func inspect(_ input: ImageInspectionInput) throws -> InspectedImage {
        try Task.checkCancellation()
        switch input {
        case .clipboard(let data):
            return try ImageInspection.inspect(data: data, name: "Clipboard image", isClipboardData: true)
        case .file(let url):
            guard url.isFileURL else { throw ImageInspectionError.unreadableFile }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data: Data
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true else { throw ImageInspectionError.unreadableFile }
                if let size = values.fileSize, size > ImageInspection.maximumBytes { throw ImageInspectionError.tooLarge }
                // Bound the actual read too, including a file that changes after the size check.
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                data = try handle.read(upToCount: ImageInspection.maximumBytes + 1) ?? Data()
            } catch let error as ImageInspectionError {
                throw error
            } catch {
                throw ImageInspectionError.unreadableFile
            }
            return try ImageInspection.inspect(data: data, name: url.lastPathComponent)
        }
    }
}
