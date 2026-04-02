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
