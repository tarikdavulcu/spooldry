import SpoolDryKit
import SwiftData
import SwiftUI

/// Adds or edits a spool in the inventory.
struct SpoolEditorView: View {
    let spool: Spool?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\DryBox.sortIndex), SortDescriptor(\DryBox.createdAt)]) private var boxes: [DryBox]

    @State private var material: MaterialCode = .pla
    @State private var brand = ""
    @State private var colorName = ""
    @State private var hasWeight = false
    @State private var grams = 1000
    @State private var boxID: UUID?
    @State private var hasDriedDate = false
    @State private var driedAt = Date()
    @State private var notes = ""
    @State private var confirmDelete = false

    private var materials: [MaterialCode] { FilamentDatabase.all.map(\.material) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Filament") {
                    Picker("Material", selection: $material) {
                        ForEach(materials, id: \.self) { m in Text(verbatim: m.shortName).tag(m) }
                    }
                    TextField("Brand", text: $brand)
                    TextField("Color", text: $colorName)
                    Toggle("Track remaining weight", isOn: $hasWeight)
                    if hasWeight {
                        Stepper(value: $grams, in: 0...5000, step: 50) {
                            LabeledContent("Remaining") { Text(verbatim: "\(grams) g").monospacedDigit() }
                        }
                    }
                }

                Section {
                    Picker("Stored in", selection: $boxID) {
                        Text("Room air").tag(UUID?.none)
                        ForEach(boxes) { b in Text(verbatim: b.name).tag(Optional(b.id)) }
                    }
                    Toggle("Drying date known", isOn: $hasDriedDate)
                    if hasDriedDate {
                        DatePicker("Last dried", selection: $driedAt, in: ...Date())
                    }
                    Button("Mark as Dried Now") {
                        hasDriedDate = true
                        driedAt = Date()
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    if let g = FilamentDatabase.guidance(for: material) {
                        Text(LocalizedStringKey(g.sensitivity.localizationKey))
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                if let spool {
                    Section {
                        if model.activeLink?.isReady == true {
                            Button {
                                save()
                                model.selectedTab = .dashboard
                                model.pendingSpoolToDry = spool.id
                            } label: {
                                Label("Dry This Spool", systemImage: "flame")
                            }
                        }
                        Button("Delete Spool", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(spool == nil ? Text("Add Spool") : Text("Edit Spool"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .confirmationDialog("Delete this spool?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Spool", role: .destructive) {
                    if let spool { context.delete(spool) }
                    try? context.save()
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let s = spool else { return }
        material = s.material
        brand = s.brand
        colorName = s.colorName
        hasWeight = s.remainingGrams != nil
        grams = s.remainingGrams ?? 1000
        boxID = s.boxID
        hasDriedDate = s.lastDriedAt != nil
        driedAt = s.lastDriedAt ?? Date()
        notes = s.notes
    }

    private func save() {
        let target = spool ?? Spool(material: material)
        target.material = material
        target.brand = brand.trimmingCharacters(in: .whitespaces)
        target.colorName = colorName.trimmingCharacters(in: .whitespaces)
        target.remainingGrams = hasWeight ? grams : nil
        target.boxID = boxID
        target.lastDriedAt = hasDriedDate ? driedAt : nil
        target.notes = notes
        if spool == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
