import SwiftUI
import GuidesCore

struct GroupEditor: View {
    let group: GuideGroup?
    let onApply: (String, CGRect, CGFloat?) throws -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void
    @State private var name: String
    @State private var scale: String
    @State private var x: String
    @State private var y: String
    @State private var width: String
    @State private var height: String
    @State private var showGeometry = false
    @State private var confirmRemoval = false
    @State private var error: String?

    init(group: GuideGroup?, frame: CGRect, onApply: @escaping (String, CGRect, CGFloat?) throws -> Void,
         onCancel: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.group = group
        self.onApply = onApply
        self.onCancel = onCancel
        self.onRemove = onRemove
        _name = State(initialValue: group?.name ?? "")
        let calibration = group?.measurements.calibration
        _scale = State(initialValue: calibration.flatMap { $0.isConfirmed ? String(Double($0.pointsPerPixel * 100)) : nil } ?? "")
        _x = State(initialValue: String(Double(frame.minX)))
        _y = State(initialValue: String(Double(frame.minY)))
        _width = State(initialValue: String(Double(frame.width)))
        _height = State(initialValue: String(Double(frame.height)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group == nil ? "New Guide Group" : "Guide Group").font(.headline)
            LabeledContent("Group name") { TextField("Name", text: $name) }
            LabeledContent("View scale") {
                TextField("Unconfirmed", text: $scale)
                Text("%")
            }
            if group?.measurements.calibration.isConfirmed != true {
                Text("Leave scale blank to measure in screen points. Use Set scale later for a known distance.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Region in screen points", isExpanded: $showGeometry) {
                if group?.measurements.history.canUndo == true || group?.measurements.history.canRedo == true {
                    Text("Changing width or height resets this group’s measurement undo history.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Grid(alignment: .leading) {
                    GridRow { coordinate("X", $x); coordinate("Y", $y) }
                    GridRow { coordinate("Width", $width); coordinate("Height", $height) }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if confirmRemoval {
                Text("Remove this group and its measurements?").font(.caption)
                HStack {
                    Button("Keep group") { confirmRemoval = false }
                    Button("Remove group", role: .destructive, action: onRemove)
                }
            } else {
                HStack {
                    if let group {
                        Button("Remove…", role: .destructive) {
                            if group.measurements.document.guides.isEmpty && group.measurements.document.area == nil { onRemove() }
                            else { confirmRemoval = true }
                        }
                    }
                    Spacer()
                    Button("Cancel", action: onCancel)
                    Button("Done") { apply() }.keyboardShortcut(.defaultAction).tint(OverlayStyle.accent)
                }
            }
        }.textFieldStyle(.roundedBorder).padding(14).frame(width: 315)
    }

    private func coordinate(_ title: String, _ value: Binding<String>) -> some View {
        LabeledContent(title) { TextField(title, text: value).frame(width: 67) }
    }

    private func apply() {
        let text = scale.trimmingCharacters(in: .whitespacesAndNewlines)
        let percent = Double(text).map { CGFloat($0) }
        if (!text.isEmpty && percent == nil) || (text.isEmpty && group?.measurements.calibration.isConfirmed == true) {
            error = "Enter a positive finite scale."
            return
        }
        guard let x = Double(x), let y = Double(y), let width = Double(width), let height = Double(height),
              [x, y, width, height].allSatisfy(\.isFinite) else {
            error = "Enter finite screen-point coordinates and dimensions."
            return
        }
        do { try onApply(name, CGRect(x: x, y: y, width: width, height: height), percent) }
        catch { self.error = error.localizedDescription }
    }
}
