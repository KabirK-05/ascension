import DesignSystem
import SwiftUI

/// The Eat tab's half of Settings: the two optional keys, the photo permission, and the
/// attribution the food sources require.
///
/// It lives here because the keys and the credits belong to this feature; Settings
/// itself is a Today surface (spec §4), so it presents this view rather than
/// reimplementing it. A key is written straight to the Keychain and never shown
/// back — a field that redisplays a secret is a secret in a screenshot.
public struct FoodDataSettingsView: View {
    private let keys: any APIKeyStore
    private let consent: any MealPhotoConsenting

    @State private var usdaEntry = ""
    @State private var claudeEntry = ""
    @State private var hasUSDA: Bool
    @State private var hasClaude: Bool
    @State private var allowsPhotos: Bool
    @Environment(\.dismiss) private var dismiss

    public init(keys: any APIKeyStore,
                consent: any MealPhotoConsenting = DefaultsMealPhotoConsent()) {
        self.keys = keys
        self.consent = consent
        _hasUSDA = State(initialValue: keys.apiKey(for: .usda) != nil)
        _hasClaude = State(initialValue: keys.apiKey(for: .anthropic) != nil)
        _allowsPhotos = State(initialValue: consent.isGranted)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("USDA key") {
                    keyField(text: $usdaEntry, stored: hasUSDA, kind: .usda)
                }

                Section("Claude key") {
                    keyField(text: $claudeEntry, stored: hasClaude, kind: .anthropic)
                }

                // The revocation half of the consent the photo flow asks for. A toggle
                // rather than a paragraph: the dialog at the point of use is where the
                // decision is explained, and this is where it is changed.
                Section {
                    Toggle("Send photos", isOn: $allowsPhotos)
                        .onChange(of: allowsPhotos) { _, allowed in
                            allowed ? consent.grant() : consent.revoke()
                        }
                }

                Section("Credits") {
                    ForEach(EatCredits.all) { credit in
                        Link(destination: credit.url) {
                            LabeledContent(credit.source, value: credit.licence)
                        }
                    }
                }
            }
            .navigationTitle("Food data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func keyField(text: Binding<String>, stored: Bool, kind: APIKeyKind) -> some View {
        SecureField("Key", text: text)
            .textContentType(.password)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        Button("Save") { save(text.wrappedValue, for: kind, field: text) }
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
        if stored {
            Button("Remove", role: .destructive) { save(nil, for: kind, field: text) }
        }
    }

    private func save(_ key: String?, for kind: APIKeyKind, field: Binding<String>) {
        try? keys.setAPIKey(key, for: kind)
        field.wrappedValue = ""
        hasUSDA = keys.apiKey(for: .usda) != nil
        hasClaude = keys.apiKey(for: .anthropic) != nil
    }
}

/// Attribution for the two food databases (spec §10). Open Food Facts is ODbL, which
/// makes this a licence term rather than a courtesy; USDA FoodData Central is CC0 and
/// is credited because it is honest to say where a number came from.
public struct EatCredit: Identifiable, Hashable, Sendable {
    public let source: String
    public let licence: String
    public let url: URL

    public var id: String { source }
}

public enum EatCredits {
    public static let all: [EatCredit] = [
        EatCredit(source: "Open Food Facts",
                  licence: "ODbL 1.0",
                  url: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")
                      ?? URL(fileURLWithPath: "/")),
        EatCredit(source: "FoodData Central",
                  licence: "CC0 1.0",
                  url: URL(string: "https://fdc.nal.usda.gov/")
                      ?? URL(fileURLWithPath: "/"))
    ]
}
