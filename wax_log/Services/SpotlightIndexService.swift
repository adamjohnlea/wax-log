import CoreData
import CoreSpotlight

/// Owns the app's Spotlight index: its name, and the fetch-and-donate paths.
///
/// Two callers share these: the app itself, after a Discogs sync or when iCloud
/// brings changes from another Mac, and the system, when it asks
/// `ReleaseEntityQuery` to rebuild an index it has lost or invalidated.
enum SpotlightIndexService {
    /// A named index is recommended over the default for app content.
    static let indexName = "VinylCrateReleases"

    static var index: CSSearchableIndex {
        CSSearchableIndex(name: indexName)
    }

    // MARK: - Reading

    /// Builds entities for every release in the collection and wantlist.
    /// Runs on a background context so a full rebuild doesn't block the UI.
    static func allEntities(
        from controller: PersistenceController = .shared
    ) async -> [ReleaseEntity] {
        let context = controller.container.newBackgroundContext()
        return await context.perform {
            let request = NSFetchRequest<Release>(entityName: "Release")
            let releases = (try? context.fetch(request)) ?? []
            return releases.map(ReleaseEntity.init(release:))
        }
    }

    /// Builds entities for specific `"<discogsId>-<listType>"` identifiers,
    /// skipping any that no longer exist.
    static func entities(
        identifiedBy identifiers: [String],
        from controller: PersistenceController = .shared
    ) async -> [ReleaseEntity] {
        let context = controller.container.newBackgroundContext()
        return await context.perform {
            identifiers.compactMap { identifier -> ReleaseEntity? in
                guard let parsed = ReleaseEntity.parseID(identifier) else { return nil }
                let request = NSFetchRequest<Release>(entityName: "Release")
                request.predicate = NSPredicate(
                    format: "discogsId == %lld AND listType == %@",
                    parsed.discogsId, parsed.listType
                )
                request.fetchLimit = 1
                return (try? context.fetch(request).first).map(ReleaseEntity.init(release:))
            }
        }
    }

    // MARK: - Writing

    /// Replaces the entire index, so records removed on another device don't
    /// linger as stale results. Use after a sync, where the whole dataset may
    /// have changed.
    static func replaceAll(
        from controller: PersistenceController = .shared
    ) async throws {
        let entities = await allEntities(from: controller)
        try await index.deleteAllSearchableItems()
        guard !entities.isEmpty else { return }
        try await index.indexAppEntities(entities)
    }

    /// Adds or updates specific entities without touching the rest of the index.
    static func donate(_ entities: [ReleaseEntity]) async throws {
        guard !entities.isEmpty else { return }
        try await index.indexAppEntities(entities)
    }

    /// Removes a single release from the index.
    static func remove(discogsId: Int64, listType: String) async throws {
        try await index.deleteAppEntities(
            identifiedBy: ["\(discogsId)-\(listType)"],
            ofType: ReleaseEntity.self
        )
    }
}
