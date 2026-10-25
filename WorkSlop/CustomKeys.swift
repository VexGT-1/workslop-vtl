import SwiftUI

// VTL: Custom Keys — write any plist key the user types, through the same
// payload/restore path as the catalog tweaks. Presets are keys found in the
// iOS 27 (24A5390f) dyld shared cache; none of them is device-verified.

/// Which preferences file a custom key is written into.
enum CustomKeyFile: String, Codable, CaseIterable, Identifiable {
    case globalManaged
    case springboardManaged
    case backboarddManaged
    case uikitManaged
    case globalHome
    case springboardHome
    case customHome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .globalManaged: return "Global (managed)"
        case .springboardManaged: return "SpringBoard (managed)"
        case .backboarddManaged: return "backboardd (managed)"
        case .uikitManaged: return "UIKit (managed)"
        case .globalHome: return "Global (user)"
        case .springboardHome: return "SpringBoard (user)"
        case .customHome: return "Other domain (user)"
        }
    }

    /// The restore write for this file. `domainName` is only used by
    /// `.customHome` (e.g. "com.apple.camera").
    func write(key: String, value: PayloadValue, domainName: String = "") -> PayloadWrite {
        switch self {
        case .globalManaged:
            return managed("FileLocation.globalPreferences", ".GlobalPreferences.plist", key, value)
        case .springboardManaged:
            return managed("FileLocation.springboard", "com.apple.springboard.plist", key, value)
        case .backboarddManaged:
            return managed("FileLocation.backboardd", "com.apple.backboardd.plist", key, value)
        case .uikitManaged:
            return managed("FileLocation.uikit", "com.apple.UIKit.plist", key, value)
        case .globalHome:
            return home(".GlobalPreferences.plist", key, value)
        case .springboardHome:
            return home("com.apple.springboard.plist", key, value)
        case .customHome:
            return home("\(domainName).plist", key, value)
        }
    }

    private func managed(_ member: String, _ file: String, _ key: String, _ value: PayloadValue) -> PayloadWrite {
        PayloadWrite(domain: .managedPreferencesDomain,
                     location: .fileLocation(member: member),
                     filePath: "/var/Managed Preferences/mobile/\(file)",
                     restorePath: "mobile/\(file)",
                     key: key, value: value)
    }

    private func home(_ file: String, _ key: String, _ value: PayloadValue) -> PayloadWrite {
        PayloadWrite(domain: .homeDomain,
                     location: .directRestorePath,
                     filePath: "/var/mobile/Library/Preferences/\(file)",
                     restorePath: "Library/Preferences/\(file)",
                     key: key, value: value)
    }
}

enum CustomKeyType: String, Codable, CaseIterable, Identifiable {
    case bool, int, double, string
    var id: String { rawValue }
}

struct CustomKeyEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var file: CustomKeyFile = .globalManaged
    var domainName: String = ""
    var key: String = ""
    var type: CustomKeyType = .bool
    var value: String = "true"
    var enabled: Bool = true
    var note: String = ""

    /// Parsed value, nil when the text does not fit the type.
    var payloadValue: PayloadValue? {
        let text = value.trimmingCharacters(in: .whitespaces)
        switch type {
        case .bool:
            switch text.lowercased() {
            case "true", "yes", "1": return .bool(true)
            case "false", "no", "0": return .bool(false)
            default: return nil
            }
        case .int: return Int(text).map { .int($0) }
        case .double: return Double(text).map { .double($0) }
        case .string: return .string(value)
        }
    }

    var isValid: Bool {
        !key.trimmingCharacters(in: .whitespaces).isEmpty && payloadValue != nil
            && (file != .customHome || !domainName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var fileLabel: String {
        file == .customHome ? domainName : file.title
    }
}

/// Persists custom keys as JSON in Documents (same pattern as CustomIconStore).
enum CustomKeyStore {
    static let featureID = "custom-keys"

    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("custom-keys.json")
    }

    static func load() -> [CustomKeyEntry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([CustomKeyEntry].self, from: data) else { return [] }
        return entries
    }

    static func save(_ entries: [CustomKeyEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static var hasEnabled: Bool {
        load().contains { $0.enabled && $0.isValid }
    }
}

final class CustomKeyModel: ObservableObject {
    @Published var entries: [CustomKeyEntry] = CustomKeyStore.load() {
        didSet { CustomKeyStore.save(entries) }
    }

    func upsert(_ entry: CustomKeyEntry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[i] = entry
        } else {
            entries.append(entry)
        }
    }

    func contains(_ preset: CustomKeyPreset) -> Bool {
        entries.contains { $0.key == preset.key && $0.file == preset.file }
    }

    func add(_ preset: CustomKeyPreset) {
        guard !contains(preset) else { return }
        entries.append(CustomKeyEntry(file: preset.file, key: preset.key, type: preset.type,
                                      value: preset.value, enabled: true, note: preset.title))
    }
}

struct CustomKeyPreset: Identifiable {
    var id: String { file.rawValue + "|" + key }
    let section: String
    let title: String
    let file: CustomKeyFile
    let key: String
    let type: CustomKeyType
    let value: String
}

enum CustomKeyPresets {
    private static func sb(_ s: String, _ t: String, _ k: String, _ v: String = "true") -> CustomKeyPreset {
        CustomKeyPreset(section: s, title: t, file: .springboardManaged, key: k, type: .bool, value: v)
    }
    private static func gp(_ s: String, _ t: String, _ k: String, _ v: String = "true",
                           _ type: CustomKeyType = .bool) -> CustomKeyPreset {
        CustomKeyPreset(section: s, title: t, file: .globalManaged, key: k, type: type, value: v)
    }

    static let all: [CustomKeyPreset] = [
        // Liquid Glass
        sb("Liquid Glass", "No glass on SpringBoard buttons", "SBDisallowGlassButtons"),
        sb("Liquid Glass", "No glass on Lock Screen", "SBDisallowGlassLockScreen"),
        gp("Liquid Glass", "Glass ignores device tilt", "SolariumUseDisplayAngle", "false"),
        gp("Liquid Glass", "No background filter behind glass", "SolariumBackgroundFilter", "false"),
        gp("Liquid Glass", "No stretchy volume HUD", "SolariumElasticHUD", "false"),
        gp("Liquid Glass", "Solid fill behind floating glass", "UISolariumFloatingContentViewEnableBackgroundFills"),
        gp("Liquid Glass", "UIKit glass master switch OFF (risky)", "_UISolariumEnabled", "false"),
        // Everywhere
        gp("Every app", "Animation speed (0.5 fast, 2 slow)", "UIAnimationDragCoefficient", "0.5", .double),
        gp("Every app", "No blurred scroll pockets", "UIHideScrollPocket"),
        gp("Every app", "No rubber-band bounce", "UIBounceEnabled", "false"),
        gp("Every app", "Hide vertical scroll bars", "UIShowsVerticalScrollIndicator", "false"),
        gp("Every app", "Flat materials instead of blur", "UISuppressesMaterialRendering"),
        gp("Every app", "No vibrancy", "UIVibrancySuppression"),
        gp("Every app", "Hide keyboard suggestion bar", "UIKeyboardNeverShowCandidateBar"),
        gp("Every app", "Alternate system font", "UIUseAlternateFont"),
        sb("Every app", "Full-width keyboard in all apps", "SBForceFullScreenKeyboardForAllApps"),
        // Display / web
        gp("Display & Web", "Websites at 120 fps", "WebKitPreferPageRenderingUpdatesNear60FPSEnabled", "false"),
        gp("Display & Web", "120 Hz unlock (may not work globally)", "CADisableMinimumFrameDurationOnPhone"),
        gp("Display & Web", "120 Hz / VRR on external displays", "CAEnableExternalHighRefreshRateAndVRR"),
        gp("Display & Web", "Metal frame interpolation", "CAAllowMetalFrameInterpolation"),
        gp("Display & Web", "Web repaint counters (debug, funny)", "WebKitShowRepaintCounter"),
        // Home Screen
        sb("Home Screen", "Hide app labels", "SBHomeHideLabels"),
        sb("Home Screen", "Hide Search pill", "SBHomeScreenShowsSearchAffordance", "false"),
        sb("Home Screen", "No icon fly-in after unlock", "SBDisableIconFlyInAnimation"),
        sb("Home Screen", "Static Clock / Calendar icons", "SBDisableLiveIcons"),
        sb("Home Screen", "App Library button in dock", "SBAppLibraryInDockEnabled"),
        // Status bar & Island
        sb("Status Bar", "Hide Dynamic Island completely", "SBSuppressDynamicIslandCompletely"),
        sb("Status Bar", "Signal as dBm number", "SBShowRSSI"),
        sb("Status Bar", "Ringer icon in status bar", "SBShowRingerState"),
        sb("Status Bar", "Dynamic Island in screenshots", "SBAlwaysShowSystemApertureInSnapshots"),
        // iPad mode
        sb("iPad Mode", "Stage Manager windowing", "SBChamoisWindowingEnabled"),
        sb("iPad Mode", "Split View / Slide Over", "SBMedusaMultitaskingEnabled"),
        sb("iPad Mode", "Every app resizable", "SBForceAllPhoneAppsToBeResizableOnResizableDisplays"),
        // System
        sb("System", "No \"No SIM\" popup", "SBSuppressNoSimAlert"),
        sb("System", "Kill Reachability", "SBReallyDisableReachability"),
        sb("System", "Camera Control works lying flat", "SBCaptureButtonDisableStationaryDetection"),
        sb("System", "Liquid button droplet hints", "SBHardwareButtonHintDropletsEnabled"),
        sb("System", "Show internal apps (internal builds)", "SBShowInternalApps"),
    ]

    static var sections: [String] {
        var seen: [String] = []
        for p in all where !seen.contains(p.section) { seen.append(p.section) }
        return seen
    }
}

struct CustomKeysView: View {
    @StateObject private var model = CustomKeyModel()
    @State private var editing: CustomKeyEntry?

    var body: some View {
        ZStack {
            SkyBackground()
            List {
                Section {
                    if model.entries.isEmpty {
                        Text("No keys yet. Add one or tap a preset.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach($model.entries) { $entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.note.isEmpty ? entry.key : entry.note)
                                Text("\(entry.key) = \(entry.value) · \(entry.fileLabel)")
                                    .font(.caption)
                                    .foregroundStyle(entry.isValid ? Color.secondary : Color.red)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editing = entry }
                            Spacer()
                            Toggle("", isOn: $entry.enabled).labelsHidden()
                        }
                    }
                    .onDelete { model.entries.remove(atOffsets: $0) }
                    Button {
                        editing = CustomKeyEntry()
                    } label: {
                        Label("Add custom key", systemImage: "plus")
                    }
                } header: {
                    Text("Your keys")
                } footer: {
                    Text("Enabled keys are sent with the next Apply. Swipe to delete. Remove Tweaks does not know about these; to undo one, set it to the default value and apply again.")
                }

                ForEach(CustomKeyPresets.sections, id: \.self) { section in
                    Section("Presets · \(section)") {
                        ForEach(CustomKeyPresets.all.filter { $0.section == section }) { preset in
                            Button {
                                model.add(preset)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.title).foregroundStyle(.primary)
                                        Text("\(preset.key) = \(preset.value)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: model.contains(preset) ? "checkmark.circle.fill" : "plus.circle")
                                }
                            }
                            .disabled(model.contains(preset))
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Custom Keys")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { entry in
            CustomKeyEditor(entry: entry) { saved in
                model.upsert(saved)
                editing = nil
            }
        }
    }
}

struct CustomKeyEditor: View {
    @State var entry: CustomKeyEntry
    let onSave: (CustomKeyEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Key") {
                    TextField("Key name, e.g. SBHomeHideLabels", text: $entry.key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Label (optional)", text: $entry.note)
                }
                Section("File") {
                    Picker("File", selection: $entry.file) {
                        ForEach(CustomKeyFile.allCases) { Text($0.title).tag($0) }
                    }
                    if entry.file == .customHome {
                        TextField("Domain, e.g. com.apple.camera", text: $entry.domainName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                Section {
                    Picker("Type", selection: $entry.type) {
                        ForEach(CustomKeyType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Value", text: $entry.value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Value")
                } footer: {
                    Text(entry.payloadValue == nil ? "Value does not match the type." : "bool: true/false. int: 5. double: 0.5.")
                }
                Toggle("Enabled", isOn: $entry.enabled)
            }
            .navigationTitle(entry.key.isEmpty ? "New key" : entry.key)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(entry) }
                        .disabled(!entry.isValid)
                }
            }
        }
    }
}
