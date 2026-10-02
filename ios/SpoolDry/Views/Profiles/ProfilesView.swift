import SpoolDryKit
import SwiftData
import SwiftUI

struct ProfilesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomFilamentProfile.createdAt) private var customProfiles: [CustomFilamentProfile]
    @AppStorage(SettingsKeys.temperatureUnit) private var unitRaw = TemperatureUnit.preferred().rawValue
    @State private var editing: FilamentProfile?
    @State private var search = ""

    private var unit: TemperatureUnit { TemperatureUnit(rawValue: unitRaw) ?? .celsius }

    private var filteredGuidance: [FilamentGuidance] {
        guard !search.isEmpty else { return FilamentDatabase.all }
        return FilamentDatabase.all.filter { $0.displayName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Values are typical starting guidance compiled from manufacturer recommendations, not universal requirements. Your filament's data sheet always wins.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("My profiles") {
                    if customProfiles.isEmpty {
                        Text("Create profiles for the exact brands you print.").foregroundStyle(.secondary)
                    }
                    ForEach(customProfiles) { stored in
                        let p = stored.profile
                        Button { editing = p } label: { ProfileRow(profile: p, unit: unit) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(customProfiles[i]) }
                        try? context.save()
                    }
                    Button {
                        editing = FilamentProfile(brand: "", material: .pla, name: "", temperature: 50, duration: 6 * 3600,
                                                  humidityTarget: 20, source: .user(reference: nil))
                    } label: {
                        Label("New Profile", systemImage: "plus")
                    }
                }
                Section("Engineering polymers") {
                    ForEach(filteredGuidance) { g in
                        NavigationLink(value: g.material) {
                            ProfileRow(profile: FilamentProfile.builtIn(g), unit: unit, guidance: g)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: Text("Search materials"))
            .navigationTitle("Filament Profiles")
            .navigationDestination(for: MaterialCode.self) { m in
                if let g = FilamentDatabase.guidance(for: m) { GuidanceDetailView(guidance: g, unit: unit) }
            }
            .sheet(item: $editing) { p in
                ProfileEditorView(profile: p, isNew: !customProfiles.contains { $0.id == p.id })
            }
        }
    }
}

private struct ProfileRow: View {
    let profile: FilamentProfile
    let unit: TemperatureUnit
    var guidance: FilamentGuidance? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.15))
                Text(String(profile.material.shortName.prefix(4)))
                    .font(.caption2.weight(.bold))
                    .minimumScaleFactor(0.5)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.brand.isEmpty ? profile.name : "\(profile.brand) \(profile.name)").font(.headline)
                Text("\(SpoolDryFormat.temperature(profile.temperature, unit: unit, fractionDigits: 0)) · \(SpoolDryFormat.duration(profile.duration))")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if let guidance, guidance.exceedsDeviceLimit {
                Image(systemName: "flame.circle")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("Needs a high-temperature dryer"))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct GuidanceDetailView: View {
    let guidance: FilamentGuidance
    let unit: TemperatureUnit

    var body: some View {
        List {
            Section {
                GuidanceSummary(guidance: guidance, unit: unit)
                LabeledContent("SpoolDry starting point") {
                    Text("\(SpoolDryFormat.temperature(guidance.suggestedCelsius, unit: unit, fractionDigits: 0)) · \(SpoolDryFormat.duration(guidance.suggestedHours * 3600))")
                        .monospacedDigit()
                }
                LabeledContent("Humidity target") { Text("< \(Int(guidance.humidityTargetPercent))% RH") }
            } footer: {
                Text("Typical starting guidance, not a manufacturer requirement. Always check your filament's data sheet.")
            }
            Section("Notes") {
                Text(LocalizedStringKey(guidance.notesKey))
            }
            Section {
                ForEach(guidance.references, id: \.self) { r in
                    Link(destination: r.url) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(r.manufacturer) – \(r.product)").font(.subheadline.weight(.semibold))
                            Text(r.summary).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Manufacturer references")
            } footer: {
                Text("Summarised from the linked official pages. Last checked \(FilamentDatabase.lastVerified.formatted(date: .abbreviated, time: .omitted)).")
            }
        }
        .navigationTitle(guidance.displayName)
    }
}

struct ProfileEditorView: View {
    @State var profile: FilamentProfile
    let isNew: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var stored: [CustomFilamentProfile]
    @AppStorage(SettingsKeys.temperatureUnit) private var unitRaw = TemperatureUnit.preferred().rawValue
    @State private var reference = ""
    @State private var hours = 6.0

    private var unit: TemperatureUnit { TemperatureUnit(rawValue: unitRaw) ?? .celsius }
    private var issues: [FilamentProfile.ValidationIssue] { profile.validate() }

    var body: some View {
        NavigationStack {
            Form {
                Section("Filament") {
                    TextField("Brand", text: $profile.brand)
                    TextField("Name", text: $profile.name)
                    Picker("Material", selection: $profile.material) {
                        ForEach(MaterialCode.allCases, id: \.self) { m in Text(m.shortName).tag(m) }
                    }
                }
                Section("Drying") {
                    Stepper(value: $profile.temperature, in: 35...70, step: 1) {
                        LabeledContent("Temperature") {
                            Text(SpoolDryFormat.temperature(profile.temperature, unit: unit, fractionDigits: 0)).monospacedDigit()
                        }
                    }
                    Stepper(value: $hours, in: 0.25...48, step: 0.25) {
                        LabeledContent("Duration") { Text(SpoolDryFormat.duration(hours * 3600)).monospacedDigit() }
                    }
                    Stepper(value: $profile.humidityTarget, in: 5...40, step: 1) {
                        LabeledContent("Humidity target") { Text("< \(Int(profile.humidityTarget))% RH") }
                    }
                }
                Section {
                    TextField("Data sheet URL or reference", text: $reference)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Notes", text: $profile.notes, axis: .vertical)
                } header: {
                    Text("Source")
                } footer: {
                    Text("Your own values are labelled as yours, never as a manufacturer recommendation.")
                }
                if issues.contains(.emptyName) {
                    Text("Enter a name.").foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle(isNew ? Text("New Profile") : Text("Edit Profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!issues.isEmpty)
                }
            }
            .onAppear {
                hours = profile.duration / 3600
                if case let .user(r) = profile.source { reference = r ?? "" }
            }
            .onChange(of: hours) { _, h in profile.duration = h * 3600 }
        }
    }

    private func save() {
        profile.source = .user(reference: reference.isEmpty ? nil : reference)
        profile.lastVerified = Date()
        if let existing = stored.first(where: { $0.id == profile.id }) {
            existing.update(from: profile)
        } else {
            context.insert(CustomFilamentProfile(from: profile))
        }
        try? context.save()
        dismiss()
    }
}
