import AscensionCore
import Foundation

/// Remote answers, kept on disk so the tab stays useful without a network.
///
/// Spec §F3 asks for cached lookups; the point is a barcode scanned once in a shop
/// still logs the next time, with no signal. Staples never come through here — they
/// are seeded locally and need no network at all.
public protocol FoodCache: Actor {
    func food(forBarcode barcode: String) -> FoodItemDTO?
    func store(_ food: FoodItemDTO, forBarcode barcode: String)
    func foods(forSearch term: String) -> [FoodItemDTO]
    func store(_ foods: [FoodItemDTO], forSearch term: String)
}

/// A cache in a single JSON file in Application Support.
///
/// One file rather than a store per entry: this is a personal app, the cache is small,
/// and a whole-file atomic write cannot leave a half-written entry behind. Writes are
/// best-effort — a cache that cannot be saved must never break logging — and the file
/// is capped so it cannot grow without bound.
public actor FileFoodCache: FoodCache {
    private struct Contents: Codable {
        var barcodes: [String: FoodItemDTO] = [:]
        var searches: [String: [FoodItemDTO]] = [:]
    }

    private let url: URL?
    private var contents: Contents
    private let searchLimit: Int

    public init(url: URL? = FileFoodCache.defaultURL(), searchLimit: Int = 40) {
        self.url = url
        self.searchLimit = searchLimit
        self.contents = url
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Contents.self, from: $0) }
            ?? Contents()
    }

    public static func defaultURL() -> URL? {
        let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return directory?.appending(path: "ascension-food-cache.json")
    }

    public func food(forBarcode barcode: String) -> FoodItemDTO? {
        contents.barcodes[barcode]
    }

    public func store(_ food: FoodItemDTO, forBarcode barcode: String) {
        contents.barcodes[barcode] = food
        persist()
    }

    public func foods(forSearch term: String) -> [FoodItemDTO] {
        contents.searches[Self.key(term)] ?? []
    }

    public func store(_ foods: [FoodItemDTO], forSearch term: String) {
        guard !foods.isEmpty else { return }
        var searches = contents.searches
        searches[Self.key(term)] = foods
        if searches.count > searchLimit {
            // Oldest-first eviction would need timestamps the cache does not keep; a
            // stable arbitrary drop is enough for a cache whose miss costs one request.
            for key in searches.keys.sorted().prefix(searches.count - searchLimit) {
                searches[key] = nil
            }
        }
        contents.searches = searches
        persist()
    }

    private static func key(_ term: String) -> String {
        term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func persist() {
        guard let url, let data = try? JSONEncoder().encode(contents) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
