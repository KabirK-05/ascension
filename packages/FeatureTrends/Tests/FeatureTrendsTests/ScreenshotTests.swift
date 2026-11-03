import DesignSystem
import SwiftUI
import Testing
import UIKit

@testable import FeatureTrends

/// Renders the tab to PNGs for the PR's light and dark screenshots
/// (`docs/DESIGN_RULES.md` §7.2).
///
/// It renders ``TrendsCards`` — the same view the screen scrolls — rather than a second
/// stack built for pictures, so what review sees is what ships. Output goes to the test
/// process's own temporary directory unless `TRENDS_SCREENSHOT_DIR` says otherwise, so
/// on CI this is a rendering assertion and writes nothing that outlives the run.
@MainActor
struct ScreenshotTests {

    static var directory: URL {
        ProcessInfo.processInfo.environment["TRENDS_SCREENSHOT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("trends-screenshots", isDirectory: true)
    }

    @Test("renders the tab in both appearances")
    func renderBothAppearances() async throws {
        let directory = Self.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        struct Shot {
            let name: String
            let snapshot: TrendsSnapshot
        }

        let shots = [
            Shot(name: "trends", snapshot: TrendsFixtures.stalled),
            Shot(name: "review", snapshot: TrendsFixtures.sundayReview)
        ]

        for shot in shots {
            let (name, snapshot) = (shot.name, shot.snapshot)
            let text = await TemplateReviewWriter().write(
                WeeklyReviewFacts(report: snapshot.weeklyReport, goals: snapshot.goals))
            let presentation = TrendsPresenter.present(
                snapshot, review: WeeklyReview.isDue(snapshot.clock.today) ? text : nil)

            for scheme in [ColorScheme.dark, .light] {
                let image = try render(presentation, scheme: scheme)
                let suffix = scheme == .dark ? "dark" : "light"
                guard let data = image.pngData() else {
                    Issue.record("could not encode \(name)-\(suffix)")
                    return
                }
                try data.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
    }

    /// An iPhone-width render of the card stack at the default type size.
    private func render(_ presentation: TrendsPresentation,
                        scheme: ColorScheme) throws -> UIImage {
        let view = TrendsCards(presentation: presentation, acceptState: .idle, accept: { _ in })
            .padding(.top, Spacing.regular)
            .frame(width: 393)
            .background(Palette.background)
            .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 393, height: nil)
        guard let image = renderer.uiImage else {
            throw ScreenshotError.renderFailed
        }
        return image
    }

    enum ScreenshotError: Error {
        case renderFailed
    }
}
