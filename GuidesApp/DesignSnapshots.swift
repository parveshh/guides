#if DEBUG
import AppKit
import GuidesCore

/// Design-review renders of Guides' own views, started with `--design-snapshots <directory>`.
/// Views are drawn through AppKit's display cache; no screen content is captured.
@MainActor
enum DesignSnapshots {
    static func run(overlay: OverlayController, directory: URL, windows: [(String, () -> Void)]) {
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            func settle() async { try? await Task.sleep(for: .milliseconds(400)) }
            overlay.edit(.guides)
            overlay.designSetViewport(CGSize(width: 1440, height: 1024))
            var ids: [UUID] = []
            overlay.designSnapshot("1-guides-solid", to: directory) { model in
                model.rulerAppearance = .solid
                for x in [360.0, 580, 900] { if let id = model.document.add(axis: .vertical, position: x) { ids.append(id) } }
                for y in [330.0, 470] { _ = model.document.add(axis: .horizontal, position: y) }
                model.document.select(Array(ids.prefix(2)))
            }
            await settle()
            overlay.designSnapshot("1-guides-solid", to: directory) { _ in }
            await overlay.designCheckGapLabels(to: directory)
            overlay.designSnapshot("2-guides-transparent", to: directory) { model in
                model.rulerAppearance = .transparent
                model.document.select([])
                // Unconfirmed scale: the ruler shows the set-scale notice instead of markers.
                model.breakpoints = (try? BreakpointSet(source: BreakpointSet.example)) ?? .empty
            }
            await settle()
            overlay.designSnapshot("2-guides-transparent", to: directory) { _ in }
            overlay.designSnapshot("3-area-tokens", to: directory) { model in
                model.rulerAppearance = .solid
                model.presentation.edit(.area)
                model.document.setArea(CGRect(x: 640, y: 380, width: 320, height: 200))
                model.document.selectArea()
                model.areaDimension = .width
                model.calibration.setScale(percent: 100)
                model.unit = .designPixels
                model.spacingScale = (try? SpacingScale(source: SpacingScale.example + "\n--card: 320px;", tolerance: "1")) ?? .empty
                model.grid.isEnabled = true
            }
            await settle()
            overlay.designSnapshot("3-area-tokens", to: directory) { _ in }
            overlay.designSnapshot("4-annotate", to: directory) { model in
                model.grid.isEnabled = false
                model.presentation.edit(.annotate)
                model.document.clear()
                for (tool, start, end) in [(AnnotationTool.rectangle, CGPoint(x: 560, y: 330), CGPoint(x: 880, y: 490))] {
                    model.annotations.setTool(tool)
                    model.annotations.begin(at: start); model.annotations.drag(to: end); model.annotations.end()
                }
                model.annotations.select(model.annotations.document.shapes.first?.id)
                model.annotations.apply(style: AnnotationStyle(color: .pink, stroke: .thin), spotlight: false, dimOpacity: 0.55)
            }
            await settle()
            overlay.designSnapshot("4-annotate", to: directory) { _ in }
            overlay.designSnapshotOptions(to: directory)
            // A compact-to-single-row transition must resize the toolbar host once SwiftUI reports its new ideal size.
            overlay.designSetViewport(CGSize(width: 760, height: 1024))
            overlay.designSnapshot("x-compact", to: directory) { $0.presentation.edit(.guides) }
            await settle()
            overlay.designSnapshot("x-compact", to: directory) { _ in }
            overlay.designSnapshot("x-compact-annotate", to: directory) { $0.presentation.edit(.annotate) }
            await settle()
            overlay.designSnapshot("x-compact-annotate", to: directory) { _ in }
            overlay.designSetViewport(CGSize(width: 1440, height: 1024))
            overlay.designSnapshot("x-single-row", to: directory) { $0.presentation.edit(.guides) }
            await settle()
            overlay.designReportToolbar("x-single-row-settled")
            overlay.pin()
            await settle()
            overlay.designSnapshot("5-pinned", to: directory) { _ in }
            overlay.hide()
            for (name, show) in windows {
                show()
                await settle()
                if let view = NSApp.keyWindow?.contentView ?? NSApp.windows.last(where: { $0.isVisible && $0.styleMask.contains(.titled) })?.contentView {
                    write(view, name: name, to: directory, crop: view.bounds.size, backdrop: false)
                }
                NSApp.keyWindow?.close()
            }
            NSApp.terminate(nil)
        }
    }

    static func write(_ view: NSView, name: String, to directory: URL, origin: CGPoint = .zero, crop: CGSize, backdrop: Bool,
                      floatingView: NSView? = nil, floatingRect: CGRect? = nil) {
        guard let source = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: source)
        guard let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(crop.width), pixelsHigh: Int(crop.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: output) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let frame = CGRect(origin: .zero, size: crop)
        if backdrop {
            // Light, mid and dark bands show how overlay elements read over different content.
            for (index, color) in [NSColor(white: 0.96, alpha: 1), NSColor(srgbRed: 0.33, green: 0.47, blue: 0.72, alpha: 1), NSColor(white: 0.1, alpha: 1)].enumerated() {
                color.setFill()
                CGRect(x: crop.width * CGFloat(index) / 3, y: 0, width: crop.width / 3, height: crop.height).fill()
            }
        } else { NSColor.windowBackgroundColor.setFill(); frame.fill() }
        source.draw(in: frame, from: CGRect(x: origin.x, y: view.bounds.height - crop.height - origin.y, width: crop.width, height: crop.height),
            operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        // Composite another Guides-owned view cache, such as a popover, at its actual window position.
        if let floatingView, let rect = floatingRect,
           let floating = floatingView.bitmapImageRepForCachingDisplay(in: floatingView.bounds) {
            floatingView.cacheDisplay(in: floatingView.bounds, to: floating)
            floating.draw(in: CGRect(x: rect.minX - origin.x, y: crop.height - rect.maxY + origin.y,
                width: rect.width, height: rect.height), from: floatingView.bounds,
                operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
        try? output.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
#endif
