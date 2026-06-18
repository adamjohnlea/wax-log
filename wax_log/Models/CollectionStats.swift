import Foundation
import CoreData

/// Summary metrics for the collection, shared by the Statistics dashboard and
/// the Collection Stats app intent so both compute the numbers the same way.
struct CollectionStats {
    let total: Int
    let artists: Int
    let genres: Int
    /// Average of releases that have a non-zero rating, or `nil` if none are rated.
    let averageRating: Double?

    init(releases: [Release]) {
        total = releases.count
        artists = Set(releases.compactMap(\.artist).filter { !$0.isEmpty }).count
        genres = Set(
            releases
                .compactMap(\.genre)
                .flatMap { $0.components(separatedBy: ", ") }
                .filter { !$0.isEmpty }
        ).count

        let rated = releases.filter { $0.rating > 0 }
        averageRating = rated.isEmpty
            ? nil
            : Double(rated.reduce(0) { $0 + Int($1.rating) }) / Double(rated.count)
    }

    /// Builds stats for the user's collection (not the wantlist).
    static func current(
        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext
    ) -> CollectionStats {
        let releases = (try? context.fetch(Release.collectionFetchRequest())) ?? []
        return CollectionStats(releases: releases)
    }

    /// Formatted average rating for display, e.g. "4.2" or "N/A".
    var averageRatingText: String {
        guard let averageRating else { return "N/A" }
        return String(format: "%.1f", averageRating)
    }

    /// A natural-language summary for Siri / intent dialog.
    var spokenSummary: String {
        guard total > 0 else {
            return "Your collection is empty. Sync from Discogs to get started."
        }
        var summary = "You have \(total) record\(total == 1 ? "" : "s") "
        summary += "from \(artists) artist\(artists == 1 ? "" : "s") "
        summary += "across \(genres) genre\(genres == 1 ? "" : "s")."
        if let averageRating {
            summary += String(format: " Your average rating is %.1f stars.", averageRating)
        }
        return summary
    }
}
