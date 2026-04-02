import Foundation
import CoreData

extension Release {
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

    var displayYear: String {
        year > 0 ? String(year) : "Unknown"
    }

    var displayRating: String {
        rating > 0 ? String(repeating: "★", count: Int(rating)) + String(repeating: "☆", count: 5 - Int(rating)) : "Not Rated"
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
