import AscensionCore
import DesignSystem
import SwiftUI

/// Settings. Answers one question: **is this connected, and to what?**
///
/// A `Form` rather than cards, because every row here is a setting and the system already
/// has the right component for that (§4.3). Each row is a noun and a value, right-aligned
/// the way Apple's own device screens read; nothing explains itself, and the three rows
/// that can be unset show a value rather than a sentence about being unset (§1.4).
///
/// Mobbin references (§7.1): ChatGPT *Remote control*, Eight Sleep *Device settings*,
/// Garmin Connect *Phone*, Matter *Connections*, Shopify *Domains*.
struct SettingsScreen: View {
    @State private var model: SettingsModel
    @State private var isEnteringToken = false
    @State private var isChoosingFolder = false
    @Environment(\.dismiss) private var dismiss

    private let composition: AppComposition

    init(composition: AppComposition) {
        self.composition = composition
        _model = State(initialValue: SettingsModel(composition: composition))
    }

    var body: some View {
        NavigationStack {
            Form {
                worker
                muse
                export
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isEnteringToken) {
                TokenSheet { model.save(token: $0) }
            }
            .fileImporter(isPresented: $isChoosingFolder,
                          allowedContentTypes: [.folder]) { result in
                if case .success(let folder) = result { model.adopt(exportFolder: folder) }
            }
            .onAppear { model.refresh() }
        }
    }

    // MARK: - Worker

    private var worker: some View {
        Section("Worker") {
            TextField("Origin", text: $model.origin)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { model.commitOrigin() }

            Button {
                isEnteringToken = true
            } label: {
                SettingRow(label: "Token", value: model.maskedToken ?? "—")
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            SettingRow(label: "Bridge", value: model.bridge.rawValue,
                       tint: model.bridge == .paired ? Palette.accent : nil)
            SettingRow(label: "Last push", value: Stamp.relative(model.lastPush))

            if model.bridge == .paired {
                Button("Sync now") { Task { await model.syncNow() } }
                    .disabled(model.isSyncing)
                if model.maskedToken != nil {
                    Button("Forget token", role: .destructive) { model.clearToken() }
                }
            }
        }
    }

    // MARK: - Muse

    private var muse: some View {
        Section("Muse") {
            Picker("Writes", selection: $model.writeMode) {
                Text("Apply").tag(MuseWriteMode.apply)
                Text("Propose").tag(MuseWriteMode.propose)
            }
            .onChange(of: model.writeMode) { _, mode in
                Task { await model.apply(writeMode: mode) }
            }

            NavigationLink("Changes") {
                ChangesScreen(composition: composition)
            }
        }
    }

    // MARK: - Export

    private var export: some View {
        Section("Export") {
            Button {
                isChoosingFolder = true
            } label: {
                SettingRow(label: "Folder", value: model.exportFolderChosen ? "Chosen" : "—")
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

/// A noun on the left, its value on the right. The whole vocabulary of this screen.
struct SettingRow: View {
    let label: String
    let value: String
    var tint: Color?

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(tint ?? Palette.secondaryText)
                .monospacedDigit()
        }
    }
}

/// Dates on this screen are relative, because the question is "how long ago", and an em
/// dash where there is no answer rather than a sentence saying there is none.
enum Stamp {
    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.relative(presentation: .numeric))
    }
}

#Preview("Settings — dark") {
    SettingsScreen(composition: AppComposition()).preferredColorScheme(.dark)
}

#Preview("Settings — light") {
    SettingsScreen(composition: AppComposition()).preferredColorScheme(.light)
}
