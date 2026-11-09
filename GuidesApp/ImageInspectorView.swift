import AppKit
import GuidesCore
import SwiftUI

struct ImageInspectorView: View {
    var model: ImageInspectorModel
    let open: () -> Void
    let paste: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToolHeader(symbol: "photo", title: "Inspect an image",
                subtitle: "Read original image pixels, independently of desktop zoom and ruler calibration.")
            HStack {
                Button("Open Image…", systemImage: "folder", action: open).help("Open Image (Command-O)")
                Button("Paste Image", systemImage: "doc.on.clipboard", action: paste).help("Paste Image (Command-V)")
                Spacer()
                if model.image != nil || model.isLoading { Button("Clear") { model.clear() } }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5))
                if let image = model.image {
                    GeometryReader { geometry in
                        Image(decorative: image.preview, scale: 1)
                            .resizable().scaledToFit()
                            .frame(width: max(0, geometry.size.width - 32), height: max(0, geometry.size.height - 32))
                            .padding(16)
                            .accessibilityLabel("Scaled preview of \(image.metadata.name)")
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo").font(.system(size: 36)).foregroundStyle(.secondary)
                        Text("Drop an image here").font(.headline)
                        Text("Or open a file or paste an image.\nPNG, JPEG, TIFF, GIF, HEIC and other Image I/O formats.\nOne image at a time, up to 100 MiB.")
                            .multilineTextAlignment(.center).font(.caption).foregroundStyle(.secondary)
                    }.padding()
                }
                if model.isLoading {
                    ProgressView("Reading image…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(minHeight: 150, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.isDropTarget ? Color.accentColor : .clear, lineWidth: 3))
            if let error = model.error {
                Text(error + (model.image == nil ? "" : " Previous image retained."))
                    .font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if let image = model.image { ToolCard { metadata(image.metadata) } }
            ToolNote("Images stay on this Mac and are discarded when this window closes.")
        }.toolWindow()
    }

    private func metadata(_ metadata: ImageMetadata) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(metadata.name).font(.headline).lineLimit(1).truncationMode(.middle).help(metadata.name)
            HStack {
                Text(metadata.dimensions).font(.title2.monospacedDigit()).textSelection(.enabled)
                Spacer()
                copyButton("Copy Dimensions", text: metadata.dimensions)
            }
            HStack {
                copyButton("Copy Width", text: metadata.widthText)
                copyButton("Copy Height", text: metadata.heightText)
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                row("Aspect ratio", metadata.aspectRatio)
                row(metadata.isClipboardData ? "Clipboard format" : "File format", metadata.format)
                row(metadata.isClipboardData ? "Clipboard data size" : "File size", byteDescription(metadata.byteCount))
                row("Alpha channel", metadata.alphaDescription)
                if metadata.imageCount > 1 {
                    row("Images", "\(metadata.imageCount) · showing image \(metadata.primaryImageIndex + 1) (primary)")
                }
            }.font(.callout)
            if metadata.hasAlpha == true {
                Text("An alpha channel can hold transparency; individual pixels are not checked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if metadata.orientation != 1 {
                Text("Orientation applied. Encoded pixels: \(metadata.encodedWidth) × \(metadata.encodedHeight).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(metadata.isClipboardData
                ? "Scaled preview. Metadata describes the clipboard representation; the original file may differ."
                : "Scaled preview. Dimensions are original image pixels, with orientation applied.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func copyButton(_ title: String, text: String) -> some View {
        Button(title) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func byteDescription(_ count: Int) -> String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)) (\(count.formatted()) bytes)"
    }
}
