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
                let suffix = scheme == .dark ? "dark" : "light"
                try write(render(presentation, scheme: scheme),
                          to: directory, named: "\(name)-\(suffix)")
            }
        }

        // The largest accessibility size, where the sparklines give up their width to the
        // numbers and every row stacks (§4.3).
        let largest = TrendsPresenter.present(TrendsFixtures.stalled)
        // At 1x: the stack is several times taller at this size, and a 3x render of it
        // is past what PNG will encode.
        try write(render(largest, scheme: .dark, typeSize: .accessibility5, scale: 1),
                  to: directory, named: "ax-max")
    }

    private func write(_ image: UIImage, to directory: URL, named name: String) throws {
        guard let data = image.pngData() else {
            throw ScreenshotError.encodeFailed(name)
        }
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// An iPhone-width render of the card stack.
    private func render(_ presentation: TrendsPresentation,
                        scheme: ColorScheme,
                        typeSize: DynamicTypeSize = .large,
                        scale: CGFloat = 3) throws -> UIImage {
        let view = TrendsCards(presentation: presentation, acceptState: .idle, accept: { _ in })
            .padding(.top, Spacing.regular)
            .frame(width: 393)
            .background(Palette.background)
            .environment(\.colorScheme, scheme)
            .dynamicTypeSize(typeSize)

        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: 393, height: nil)
        guard let image = renderer.uiImage else {
            throw ScreenshotError.renderFailed
        }
        return image
    }

    enum ScreenshotError: Error {
        case renderFailed
        case encodeFailed(String)
    }
}
