import DesignSystem
import SwiftUI

/// The Eat tab's half of Settings: the USDA key, and the attribution the food sources
/// require.
///
/// It lives here because the key and the credits belong to this feature; Settings
/// itself is a Today surface (spec §4), so it presents this view rather than
/// reimplementing it. The key is written straight to the Keychain and never shown
/// back — a field that redisplays a secret is a secret in a screenshot.
public struct FoodDataSettingsView: View {
    private let keys: any APIKeyStore

    @State private var entry = ""
    @State private var isStored: Bool
    @Environment(\.dismiss) private var dismiss

    public init(keys: any APIKeyStore) {
        self.keys = keys
        _isStored = State(initialValue: keys.apiKey(for: .usda) != nil)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("USDA key") {
                    SecureField("Key", text: $entry)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Save") { save(entry) }
                        .disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
                    if isStored {
                        Button("Remove", role: .destructive) { save(nil) }
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

    private func save(_ key: String?) {
        try? keys.setAPIKey(key, for: .usda)
        entry = ""
        isStored = keys.apiKey(for: .usda) != nil
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
