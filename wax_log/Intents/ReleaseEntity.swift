import AppIntents
import CoreData
import CoreSpotlight
import UniformTypeIdentifiers

/// A value-type representation of a `Release` for App Intents and Spotlight.
///
/// Core Data managed objects aren't `Sendable`, so this entity copies the
/// fields it needs as value types. Its identity is `"<discogsId>-<listType>"`,
/// which is stable across CloudKit re-imports (Discogs IDs never change) and
/// unique across the same album appearing in both the collection and wantlist.
struct ReleaseEntity: AppEntity, IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Record"
    static var defaultQuery = ReleaseEntityQuery()

    let id: String
    let discogsId: Int64
    let listType: String
    let title: String
    let artist: String
    let displayArtist: String
    let year: Int32
    let genre: String
    let label: String
    let format: String
    let country: String
    let rating: Int16
    let imageURL: String?

    var displayRepresentation: DisplayRepresentation {
        var parts: [String] = [displayArtist]
        if year > 0 { parts.append(String(year)) }
        let subtitle = parts.joined(separator: " • ")

        if let imageURL, let url = URL(string: imageURL) {
            return DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)", image: .init(url: url))
        }
        return DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    /// Extra Spotlight metadata so searches by artist, genre, or label surface
    /// the album even though the display title is the album name.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = title
        attributes.album = title
        attributes.artist = displayArtist
        attributes.contentDescription = [displayArtist, genre, label, format]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
        attributes.keywords = [artist, displayArtist, genre, label, format, country, listType]
            .filter { !$0.isEmpty }
        return attributes
    }
}

extension ReleaseEntity {
    /// Builds an entity from a managed object. Call inside the object's context
    /// `perform` block so property access is thread-safe.
    init(release: Release) {
        let listType = release.listType ?? "collection"
        self.init(
            id: "\(release.discogsId)-\(listType)",
            discogsId: release.discogsId,
            listType: listType,
            title: release.title ?? "Untitled",
            artist: release.artist ?? "",
            displayArtist: release.displayArtist,
            year: release.year,
            genre: release.genre ?? "",
            label: release.label ?? "",
            format: release.format ?? "",
            country: release.country ?? "",
            rating: release.rating,
            imageURL: release.imageURL
        )
    }

    /// Splits an entity ID back into its `(discogsId, listType)` components.
    static func parseID(_ id: String) -> (discogsId: Int64, listType: String)? {
        guard let dash = id.firstIndex(of: "-"),
              let discogsId = Int64(id[..<dash]) else {
            return nil
        }
        return (discogsId, String(id[id.index(after: dash)...]))
    }
}

// MARK: - Query

/// Locates `ReleaseEntity` instances for Siri, Spotlight, and Shortcuts.
/// Freeform string matching reuses the in-app `SearchService` query language.
struct ReleaseEntityQuery: EntityStringQuery {
    // Queries run on the main context: result sets are small (capped below) and
    // these run only when Siri/Spotlight/Shortcuts ask, never on a hot path.
    // Async requirements permit a main-actor implementation.

    @MainActor
    func entities(for identifiers: [ReleaseEntity.ID]) async throws -> [ReleaseEntity] {
        let context = PersistenceController.shared.container.viewContext
        return identifiers.compactMap { identifier -> ReleaseEntity? in
            guard let parsed = ReleaseEntity.parseID(identifier) else { return nil }
            let request = NSFetchRequest<Release>(entityName: "Release")
            request.predicate = NSPredicate(
                format: "discogsId == %lld AND listType == %@",
                parsed.discogsId, parsed.listType
            )
            request.fetchLimit = 1
            guard let release = try? context.fetch(request).first else { return nil }
            return ReleaseEntity(release: release)
        }
    }

    @MainActor
    func entities(matching string: String) async throws -> [ReleaseEntity] {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Release>(entityName: "Release")
        request.predicate = SearchService.predicate(from: string)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)]
        request.fetchLimit = 50
        let releases = (try? context.fetch(request)) ?? []
        return releases.map(ReleaseEntity.init(release:))
    }

    @MainActor
    func suggestedEntities() async throws -> [ReleaseEntity] {
        let context = PersistenceController.shared.container.viewContext
        let request = Release.collectionFetchRequest()
        request.fetchLimit = 25
        let releases = (try? context.fetch(request)) ?? []
        return releases.map(ReleaseEntity.init(release:))
    }
}
