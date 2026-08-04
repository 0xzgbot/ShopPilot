import SwiftUI
import ShopPilotCore

/// SPK-0308 — keep-out zone management panel (Cut stage left pane).
/// Create / edit / toggle / delete zones; the same geometry powers the
/// preview overlay and the save-time violation warning.
struct KeepOutZonesPanel: View {
    @ObservedObject var session: AppSession

    @State private var showEditor = false
    @State private var editingZone: KeepOutZone?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                Text("KEEP-OUT ZONES")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    editingZone = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Add a keep-out zone")
            }

            if session.keepOutZones.isEmpty {
                Text("No zones — add one to keep toolpaths off clamps or fixtures.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(session.keepOutZones) { zone in
                    HStack(spacing: 5) {
                        Image(systemName: "hand.raised")
                            .font(.system(size: 9))
                            .foregroundStyle(zone.isActive ? Color.red : Color.secondary)
                        Text(zone.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { zone.isActive },
                            set: { _ in session.toggleKeepOutZone(id: zone.id) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .help("Active zones block/warn at save")
                        Button {
                            editingZone = zone
                            showEditor = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Edit zone")
                        Button {
                            _ = session.removeKeepOutZone(id: zone.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Delete zone")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25))
        )
        .sheet(isPresented: $showEditor) {
            KeepOutZoneEditor(
                zone: editingZone,
                onSave: { zone in
                    // Editing replaces the old zone (stable id semantics).
                    if let old = editingZone {
                        _ = session.removeKeepOutZone(id: old.id)
                    }
                    session.addKeepOutZone(zone)
                    showEditor = false
                }
            )
        }
    }
}

/// Add/edit sheet: name + type + per-type geometry fields.
private struct KeepOutZoneEditor: View {
    /// The zone being edited (nil = create new).
    let zone: KeepOutZone?
    let onSave: (KeepOutZone) -> Void

    @State private var name = ""
    @State private var type: KeepOutZoneType = .rectangle
    @State private var rectX = 0.0
    @State private var rectY = 0.0
    @State private var rectW = 20.0
    @State private var rectH = 20.0
    @State private var circleCX = 0.0
    @State private var circleCY = 0.0
    @State private var circleR = 20.0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(zone == nil ? "Add Keep-Out Zone" : "Edit Keep-Out Zone")
                .font(.headline)

            TextField("Zone name", text: $name)

            Picker("Type", selection: $type) {
                Text("Rectangle").tag(KeepOutZoneType.rectangle)
                Text("Circle").tag(KeepOutZoneType.circle)
            }
            .pickerStyle(.segmented)

            Group {
                switch type {
                case .rectangle:
                    TextField("X", value: $rectX, format: .number)
                    TextField("Y", value: $rectY, format: .number)
                    TextField("Width", value: $rectW, format: .number)
                    TextField("Height", value: $rectH, format: .number)
                case .circle:
                    TextField("Center X", value: $circleCX, format: .number)
                    TextField("Center Y", value: $circleCY, format: .number)
                    TextField("Radius", value: $circleR, format: .number)
                case .polygon:
                    Text("Polygon entry arrives in a later pass — use rectangle or circle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save Zone") {
                    let newZone: KeepOutZone
                    switch type {
                    case .rectangle:
                        newZone = KeepOutZone(
                            name: name.isEmpty ? "Zone \(Int(rectX)),\(Int(rectY))" : name,
                            type: .rectangle,
                            rectMinX: min(rectX, rectX + rectW),
                            rectMinY: min(rectY, rectY + rectH),
                            rectMaxX: max(rectX, rectX + rectW),
                            rectMaxY: max(rectY, rectY + rectH)
                        )
                    case .circle:
                        newZone = KeepOutZone(
                            name: name.isEmpty ? "Circle" : name,
                            type: .circle,
                            circleCenter: VectorPoint(x: circleCX, y: circleCY),
                            circleRadiusMm: abs(circleR)
                        )
                    case .polygon:
                        newZone = KeepOutZone(name: name.isEmpty ? "Zone" : name, type: .polygon)
                    }
                    onSave(newZone)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear {
            guard let zone else { return }
            name = zone.name
            type = zone.type
            if let minX = zone.rectMinX, let maxX = zone.rectMaxX,
               let minY = zone.rectMinY, let maxY = zone.rectMaxY {
                rectX = min(minX, maxX)
                rectY = min(minY, maxY)
                rectW = abs(maxX - minX)
                rectH = abs(maxY - minY)
            }
            if let center = zone.circleCenter, let radius = zone.circleRadiusMm {
                circleCX = center.x
                circleCY = center.y
                circleR = radius
            }
        }
    }
}
