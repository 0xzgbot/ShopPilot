import SwiftUI
import ShopPilotCore

// MARK: - Sheet List Row

/// A single row in the sheet list, showing name, dimensions, and material.
private struct SheetRowView: View {
    let sheet: Sheet
    let isSelected: Bool
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Sheet name
            Text(sheet.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Dimensions
            Text("\(Int(sheet.width)) × \(Int(sheet.depth)) × \(Int(sheet.height)) mm")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            // Material
            if let material = sheet.material {
                Text(material.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("No material")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineLimit(1)
            }
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove sheet")
            .frame(width: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}

// MARK: - Sheet List View

/// A panel that lists all sheets in a job, with add/remove controls and selection.
public struct SheetListView: View {
    
    /// The current list of sheets.
    @Binding var sheets: [Sheet]
    
    /// The ID of the currently selected sheet.
    @Binding var selectedSheetId: UUID?
    
    /// Closure called when the user wants to add a new sheet.
    /// If nil, a default sheet is created; otherwise the caller handles creation.
    var onAddSheet: (() -> Sheet)? = nil

    /// SPK-0800 — session-backed removal (undo + dirty + shape cleanup).
    /// When nil the view mutates the binding directly.
    var onRemoveSheet: ((UUID) -> Void)? = nil

    /// SPK-0800 — session-backed selection (undo + dirty + status).
    /// When nil the view mutates the binding directly.
    var onSelectSheet: ((UUID) -> Void)? = nil
    
    public init(
        sheets: Binding<[Sheet]>,
        selectedSheetId: Binding<UUID?>,
        onAddSheet: (() -> Sheet)? = nil,
        onRemoveSheet: ((UUID) -> Void)? = nil,
        onSelectSheet: ((UUID) -> Void)? = nil
    ) {
        self._sheets = sheets
        self._selectedSheetId = selectedSheetId
        self.onAddSheet = onAddSheet
        self.onRemoveSheet = onRemoveSheet
        self.onSelectSheet = onSelectSheet
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SHEETS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("(\(sheets.count))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Sheet list
            if sheets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.on.square")
                        .font(.title3)
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No sheets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tap + to add a sheet")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(sheets) { sheet in
                            SheetRowView(
                                sheet: sheet,
                                isSelected: selectedSheetId == sheet.id,
                                onRemove: { removeSheet(id: sheet.id) }
                            )
                            .onTapGesture {
                                if let onSelectSheet {
                                    onSelectSheet(sheet.id)
                                } else {
                                    selectedSheetId = sheet.id
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Divider()
            
            // Add button
            HStack {
                Button(action: addSheet) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Sheet")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 12)
        }
        .alert("Remove Sheet", isPresented: $showingRemoveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                if let id = sheetToRemove {
                    if let onRemoveSheet {
                        onRemoveSheet(id)
                    } else {
                        _sheets.wrappedValue.removeAll { $0.id == id }
                        if selectedSheetId == id {
                            selectedSheetId = nil
                        }
                    }
                }
            }
        } message: {
            if let name = sheetToRemoveName {
                Text("Are you sure you want to remove \"\(name)\"?")
            }
        }
    }
    
    // MARK: - Actions
    
    private func addSheet() {
        if let factory = onAddSheet {
            let newSheet = factory()
            sheets.append(newSheet)
            selectedSheetId = newSheet.id
        } else {
            let newSheet = Job.makeDefaultSheet()
            sheets.append(newSheet)
            selectedSheetId = newSheet.id
        }
    }
    
    private func removeSheet(id: UUID) {
        let sheet = sheets.first { $0.id == id }
        sheetToRemove = id
        sheetToRemoveName = sheet?.name
        showingRemoveAlert = true
    }
    
    // MARK: - State
    
    @State private var showingRemoveAlert = false
    @State private var sheetToRemove: UUID? = nil
    @State private var sheetToRemoveName: String? = nil
}

// MARK: - Double-sided setup (SPK-0801)

/// Pairs two sheets as front/back of a double-sided job and flips the design
/// surface between sides. Reads + writes the session's double-sided config;
/// single-sided documents show a one-line enable action.
public struct DoubleSidedSetupView: View {
    @ObservedObject var session: AppSession
    @State private var backSheetID: UUID?
    @State private var alignment: AlignmentMethod = .registrationMarks

    init(session: AppSession) {
        self.session = session
        if let cfg = session.job.doubleSidedConfig {
            _backSheetID = State(initialValue: cfg.backSheetID)
            _alignment = State(initialValue: cfg.alignmentMethod)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Double-Sided Job", systemImage: "square.split.2x1")
                    .font(.headline)
                Spacer()
                if session.job.isDoubleSided {
                    Text("Front ⇄ Back")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let cfg = session.job.doubleSidedConfig {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(sheetName(cfg.frontSheetID))
                            .font(.callout.weight(.medium))
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(sheetName(cfg.backSheetID))
                            .font(.callout.weight(.medium))
                    }
                    Text("Alignment: \(cfg.alignmentMethod.displayName) · Back Z offset \(String(format: "%.1f", cfg.backSideZOffset))mm · Rotation \(String(format: "%.0f", cfg.backSideRotation))°")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("Flip Side") { session.flipJobSide() }
                            .buttonStyle(.borderedProminent)
                        Button("Unpair") { session.clearDoubleSided() }
                            .buttonStyle(.bordered)
                    }
                }
            } else if session.job.sheets.count >= 2 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pair two sheets as the front and back of the same stock.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Back Sheet", selection: Binding(
                        get: { backSheetID ?? session.job.sheets.first(where: { $0.id != session.activeSheetID })?.id ?? session.job.sheets[0].id },
                        set: { backSheetID = $0 }
                    )) {
                        ForEach(Array(session.job.sheets.enumerated()), id: \.element.id) { _, sheet in
                            Text(sheet.name).tag(sheet.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 240)

                    Picker("Alignment", selection: $alignment) {
                        ForEach([AlignmentMethod.registrationMarks, .edgeAlignment, .gridAlignment, .manualOffset], id: \.rawValue) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 240)

                    Button("Pair as Double-Sided") {
                        guard let front = session.activeSheetID ?? session.job.sheets.first?.id,
                              let back = backSheetID ?? session.job.sheets.first(where: { $0.id != front })?.id else { return }
                        if session.setDoubleSided(frontSheetID: front, backSheetID: back, alignmentMethod: alignment) {
                            session.flipJobSide()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Add a second sheet to create a double-sided job.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func sheetName(_ id: UUID) -> String {
        session.job.sheets.first(where: { $0.id == id })?.name ?? "—"
    }
}

// MARK: - Rotary setup (SPK-0903)

/// Job-level rotary machining setup: stock diameter + axis length. Wrapped
/// Fluting and Rotary Wrap strategies default their stock Ø from here (per-op
/// params still override). Persisted on the Job via the session.
public struct RotarySetupView: View {
    @ObservedObject var session: AppSession
    @State private var diameter = "50.0"
    @State private var axisLength = "150.0"
    @State private var direction: RotaryDirection = .clockwise

    init(session: AppSession) {
        self.session = session
        if let cfg = session.job.rotaryConfig {
            _diameter = State(initialValue: String(format: "%.1f", cfg.diameter))
            _axisLength = State(initialValue: String(format: "%.1f", cfg.axisLength))
            _direction = State(initialValue: cfg.direction)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Rotary Machining", systemImage: "rotate.3d")
                    .font(.headline)
                Spacer()
                if session.job.rotaryConfig != nil {
                    Text("Ø\(String(format: "%.1f", session.job.rotaryConfig?.diameter ?? 0))mm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if session.job.rotaryConfig != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(
                        format: "Stock Ø%.1fmm × %.1fmm · %@ · wrap %@",
                        session.job.rotaryConfig?.diameter ?? 0,
                        session.job.rotaryConfig?.axisLength ?? 0,
                        (session.job.rotaryConfig?.direction == .clockwise) ? "CW" : "CCW",
                        (session.job.rotaryConfig?.wrapEnabled ?? true) ? "on" : "off"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("Edit…") { showEditor = true }
                            .buttonStyle(.bordered)
                        Button("Remove") { session.clearRotaryConfig() }
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set the rotary stock diameter so wrap/fluting ops wrap the right cylinder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Configure Rotary…") { showEditor = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $showEditor) {
            editor
        }
    }

    @State private var showEditor = false

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rotary Stock Setup")
                .font(.headline)
            TextField("Stock Ø (mm)", text: $diameter)
                .textFieldStyle(.roundedBorder)
            TextField("Axis length (mm)", text: $axisLength)
                .textFieldStyle(.roundedBorder)
            Picker("Direction", selection: $direction) {
                Text("Clockwise (CW)").tag(RotaryDirection.clockwise)
                Text("Counter-clockwise (CCW)").tag(RotaryDirection.counterClockwise)
            }
            .pickerStyle(.segmented)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { showEditor = false }
                    .buttonStyle(.bordered)
                Button("Save") {
                    let d = Double(diameter) ?? 50.0
                    let a = Double(axisLength) ?? 150.0
                    if session.setRotaryConfig(diameter: d, axisLength: a, direction: direction) {
                        showEditor = false
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
struct SheetListView_Previews: PreviewProvider {
    static var previews: some View {
        @State var sheets = [
            Sheet(name: "Face 1", width: 600, depth: 400, height: 25),
            Sheet(name: "Face 2", width: 800, depth: 500, height: 30),
        ]
        @State var selectedId: UUID? = sheets[0].id
        
        return SheetListView(sheets: $sheets, selectedSheetId: $selectedId)
            .frame(width: 300, height: 400)
    }
}
#endif
