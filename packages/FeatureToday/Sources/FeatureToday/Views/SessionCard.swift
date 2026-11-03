import AscensionCore
import DesignSystem
import SwiftUI

/// What the program prescribes today, and the one action on this screen.
///
/// The card renders nothing on a rest day or a stand-down: `TodayPresenter` hands it a
/// session only when there is one, so this never has to print "Rest day" under a heading
/// that already says it.
///
/// **Send to Watch does not schedule anything here.** Scheduling is WorkoutKit's job and
/// belongs to the Train ticket, so the action arrives as an injected closure and the
/// button exists only when the shell supplied one. This package imports no other
/// feature and no WorkoutKit.
struct SessionCard: View {
    let plan: SessionPlan
    let sendToWatch: ((SessionKind) async throws -> Void)?

    /// Where the send has got to. A failure is a control that says `Retry`, not a
    /// sentence and not an alert (§1.4).
    private enum Send: Equatable {
        case idle
        case sending
        case sent
        case failed
    }

    @State private var send: Send = .idle

    var body: some View {
        StatCard("Session") {
            VStack(alignment: .leading, spacing: Spacing.regular) {
                Text(plan.name)
                    .font(Typography.heroValue)
                    .foregroundStyle(Palette.primaryText)
                    .accessibilityLabel("Session")
                    .accessibilityValue(plan.name)
                if plan.exercises > 0 {
                    ValueRow("Exercises", value: plan.exercises.formatted())
                }
                if sendToWatch != nil {
                    sendButton
                }
            }
        }
    }

    private var sendButton: some View {
        Button(action: start) {
            HStack(spacing: Spacing.snug) {
                icon
                Text(buttonText)
            }
            .font(Typography.label)
            .foregroundStyle(buttonColour)
            .padding(.vertical, Spacing.snug)
            .padding(.horizontal, Spacing.regular)
            .frame(maxWidth: .infinity)
            .background(
                Palette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(send == .sending)
        .accessibilityLabel(buttonText)
        .accessibilityValue(plan.name)
        .animation(.easeOut(duration: 0.2), value: send)
    }

    @ViewBuilder
    private var icon: some View {
        switch send {
        case .sending:
            ProgressView().controlSize(.small)
        case .sent:
            // An SF Symbol for a status that has no words (§2.3).
            Image(systemName: "checkmark")
        case .idle, .failed:
            Image(systemName: "applewatch")
        }
    }

    private var buttonText: String {
        send == .failed ? "Retry" : "Send to Watch"
    }

    private var buttonColour: Color {
        switch send {
        case .failed: return Palette.critical
        case .sent: return Palette.accent
        case .idle, .sending: return Palette.primaryText
        }
    }

    private func start() {
        guard let sendToWatch, send != .sending else { return }
        send = .sending
        Task {
            do {
                try await sendToWatch(plan.kind)
                send = .sent
            } catch {
                send = .failed
            }
        }
    }
}
