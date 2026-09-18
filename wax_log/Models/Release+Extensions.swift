import Foundation
import CoreData

/// `nonisolated` because these are pure transforms of the object's own stored
/// attributes, read from background contexts as well as the main one (Spotlight
/// indexing builds entities on a background context). Core Data safety comes
/// from the owning context's queue, not from main-actor isolation.
nonisolated extension Release {
    var isCollection: Bool { listType == "collection" }
    var isWantlist: Bool { listType == "wantlist" }

    struct TrackInfo {
        let position: String
        let title: String
        let duration: String
    }

    struct CreditInfo {
        let name: String
        let role: String
    }

    struct IdentifierInfo {
        let type: String
        let value: String
    }

    struct VideoInfo {
        let uri: String
        let title: String
    }

    struct SuggestedPrice {
        let currency: String
        let value: Double
    }

    /// An estimated market value for this copy, with the basis it was derived from.
    struct EstimatedValue {
        enum Basis {
            /// Suggested price for the release's own media condition.
            case condition(String)
            /// No usable media condition — assumed VG+ by collector convention.
            case assumedVGPlus
            /// No sales history data — cheapest copy currently listed, any condition.
            case lowestListing
        }

        let amount: Double
        let currency: String
        let basis: Basis

        var formattedAmount: String {
            amount.formatted(.currency(code: currency))
        }

        var basisDescription: String {
            switch basis {
            case .condition(let condition): "Based on media condition: \(condition)"
            case .assumedVGPlus: "Estimate assumes VG+ — no condition set"
            case .lowestListing: "Lowest listing on Discogs — no sales history data"
            }
        }
    }

    /// The condition grade assumed when a release has no media condition set.
    static let assumedConditionKey = "Very Good Plus (VG+)"

    struct ImageInfo {
        let type: String
        let uri: String
        let uri150: String
        let width: Int
        let height: Int

        var typeLabel: String {
            switch type {
            case "primary": "Primary"
            case "secondary": "Secondary"
            default: type.capitalized
            }
        }
    }

    var decodedTracklist: [TrackInfo]? {
        guard let tracklist, let data = tracklist.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return array.compactMap { dict in
            guard let title = dict["title"] as? String else { return nil }
            return TrackInfo(
                position: dict["position"] as? String ?? "",
                title: title,
                duration: dict["duration"] as? String ?? ""
            )
        }
    }

    var decodedCredits: [CreditInfo]? {
        guard let credits, let data = credits.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return array.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            return CreditInfo(
                name: name,
                role: dict["role"] as? String ?? ""
            )
        }
    }

    var decodedIdentifiers: [IdentifierInfo]? {
        guard let identifiers, let data = identifiers.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return array.compactMap { dict in
            guard let type = dict["type"] as? String,
                  let value = dict["value"] as? String else { return nil }
            return IdentifierInfo(type: type, value: value)
        }
    }

    var decodedAdditionalImages: [ImageInfo]? {
        guard let additionalImages, let data = additionalImages.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return array.compactMap { dict in
            guard let type = dict["type"] as? String,
                  let uri = dict["uri"] as? String else { return nil }
            return ImageInfo(
                type: type,
                uri: uri,
                uri150: dict["uri150"] as? String ?? "",
                width: dict["width"] as? Int ?? 0,
                height: dict["height"] as? Int ?? 0
            )
        }
    }

    var decodedVideos: [VideoInfo]? {
        guard let videos, let data = videos.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return array.compactMap { dict in
            guard let uri = dict["uri"] as? String else { return nil }
            return VideoInfo(
                uri: uri,
                title: dict["title"] as? String ?? ""
            )
        }
    }

    /// Suggested prices keyed by media condition, e.g. "Very Good Plus (VG+)".
    var decodedPriceSuggestions: [String: SuggestedPrice]? {
        guard let priceSuggestions, let data = priceSuggestions.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            return nil
        }
        var suggestions: [String: SuggestedPrice] = [:]
        for (condition, entry) in object {
            guard let value = entry["value"] as? Double,
                  let currency = entry["currency"] as? String else { continue }
            suggestions[condition] = SuggestedPrice(currency: currency, value: value)
        }
        return suggestions
    }

    /// Estimated value for this copy: the suggested price for its media condition,
    /// falling back to VG+ when ungraded, then to the lowest current listing when
    /// the release has no sales history. `nil` when no price data is available.
    var estimatedValue: EstimatedValue? {
        if let suggestions = decodedPriceSuggestions, !suggestions.isEmpty {
            if let condition = mediaCondition, let match = suggestions[condition] {
                return EstimatedValue(amount: match.value, currency: match.currency, basis: .condition(condition))
            }
            if let assumed = suggestions[Self.assumedConditionKey] {
                return EstimatedValue(amount: assumed.value, currency: assumed.currency, basis: .assumedVGPlus)
            }
        }
        if lowestPrice > 0 {
            return EstimatedValue(amount: lowestPrice, currency: priceCurrency ?? "USD", basis: .lowestListing)
        }
        return nil
    }

    /// All images: primary (from imageURL) + additional images
    var allImages: [ImageInfo] {
        var images: [ImageInfo] = []
        if let url = imageURL, !url.isEmpty {
            images.append(ImageInfo(type: "primary", uri: url, uri150: "", width: 0, height: 0))
        }
        if let additional = decodedAdditionalImages {
            images.append(contentsOf: additional)
        }
        return images
    }

    /// Artist name with Discogs disambiguation numbers stripped for display.
    /// e.g. "Jack White (2)" → "Jack White", "Wynton Marsalis, Edita Gruberova, Ray... (3)" → "Wynton Marsalis, Edita Gruberova, Ray..."
    var displayArtist: String {
        guard let artist, !artist.isEmpty else { return "Unknown Artist" }
        // Remove trailing " (N)" from each comma-separated artist
        return artist
            .components(separatedBy: ", ")
            .map { $0.replacingOccurrences(of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression) }
            .joined(separator: ", ")
    }

    var displayYear: String {
        year > 0 ? String(year) : "Unknown"
    }

    var displayRating: String {
        rating > 0 ? String(repeating: "★", count: Int(rating)) + String(repeating: "☆", count: 5 - Int(rating)) : "Not Rated"
    }

    /// Spoken rating for VoiceOver, since `displayRating`'s star glyphs read poorly.
    var accessibilityRating: String {
        rating > 0 ? "Rated \(rating) out of 5" : "Not rated"
    }

    static func collectionFetchRequest() -> NSFetchRequest<Release> {
        let request = NSFetchRequest<Release>(entityName: "Release")
        request.predicate = NSPredicate(format: "listType == %@", "collection")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)]
        return request
    }

    static func wantlistFetchRequest() -> NSFetchRequest<Release> {
        let request = NSFetchRequest<Release>(entityName: "Release")
        request.predicate = NSPredicate(format: "listType == %@", "wantlist")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)]
        return request
    }
}
