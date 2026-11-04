import DesignSystem
import SwiftUI

/// Where the Worker's device token is typed in, once.
///
/// A `SecureField`, and the value never leaves this view except into the Keychain: the
/// token is the Worker's own `DEVICE_TOKEN` secret, so it is never logged, never put in an
/// error and never shown again — Settings shows four characters behind dots afterwards.
///
/// Save stays disabled until the field holds something long enough to be the real secret,
/// which is the control doing the explaining instead of a line of text under it (§1.4).
struct TokenSheet: View {
    /// Returns whether the token was kept, which is what decides if the sheet closes.
    let save: (String) -> Bool

    @State private var token = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                SecureField("Token", text: $token)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(commit)
            }
            .navigationTitle("Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit)
                        .disabled(token.count < RemoteSettings.minimumTokenLength)
                }
            }
        }
    }

    private func commit() {
        guard save(token) else { return }
        token = ""
        dismiss()
    }
}
