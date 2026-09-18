import AppIntents
import CoreData
import CoreSpotlight

/// Owns the app's Spotlight index: its name, and the fetch-and-donate paths.
///
/// Two callers share these: the app itself, after a Discogs sync or when iCloud
/// brings changes from another Mac, and the system, when it asks
/// `ReleaseEntityQuery` to rebuild an index it has lost or invalidated.
enum SpotlightIndexService {
    /// A named index is recommended over the default for app content.
    nonisolated static let indexName = "VinylCrateReleases"

    // MARK: - Reading

    /// Builds entities for every release, using the app's shared store.
    ///
    /// The `from:` overloads take an explicit controller rather than defaulting
    /// to `.shared`: a default argument expression doesn't inherit the enclosing
    /// main-actor isolation, so `= .shared` wouldn't compile cleanly.
    static func allEntities() async -> [ReleaseEntity] {
        await allEntities(from: .shared)
    }

    /// Builds entities for every release in the collection and wantlist.
    /// Runs on a background context so a full rebuild doesn't block the UI.
    static func allEntities(
        from controller: PersistenceController
    ) async -> [ReleaseEntity] {
        let context = controller.container.newBackgroundContext()
        return await context.perform {
            let request = NSFetchRequest<Release>(entityName: "Release")
            let releases = (try? context.fetch(request)) ?? []
            return releases.map(ReleaseEntity.init(release:))
        }
    }

    /// Builds entities for specific identifiers, using the app's shared store.
    static func entities(identifiedBy identifiers: [String]) async -> [ReleaseEntity] {
        await entities(identifiedBy: identifiers, from: .shared)
    }

    /// Builds entities for specific `"<discogsId>-<listType>"` identifiers,
    /// skipping any that no longer exist.
    static func entities(
        identifiedBy identifiers: [String],
        from controller: PersistenceController
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

    /// Replaces the entire index from the app's shared store.
    static func replaceAll() async throws {
        try await replaceAll(from: .shared)
    }

    /// Replaces the entire index, so records removed on another device don't
    /// linger as stale results. Use after a sync, where the whole dataset may
    /// have changed.
    static func replaceAll(
        from controller: PersistenceController
    ) async throws {
        let entities = await allEntities(from: controller)
        try await deleteEverything()
        try await donate(entities)
    }

    // The writers below are `nonisolated` so each creates and uses its
    // `CSSearchableIndex` entirely within one isolation domain. The index type
    // isn't `Sendable`, so touching a shared one across an `await` from the main
    // actor would be sending it. Only `[ReleaseEntity]` crosses, which is safe.

    /// Adds or updates specific entities without touching the rest of the index.
    nonisolated static func donate(_ entities: [ReleaseEntity]) async throws {
        guard !entities.isEmpty else { return }
        try await CSSearchableIndex(name: indexName).indexAppEntities(entities)
    }

    /// Removes a single release from the index.
    nonisolated static func remove(discogsId: Int64, listType: String) async throws {
        try await CSSearchableIndex(name: indexName).deleteAppEntities(
            identifiedBy: ["\(discogsId)-\(listType)"],
            ofType: ReleaseEntity.self
        )
    }

    /// Empties the index entirely. Used when resetting all app data.
    nonisolated static func deleteEverything() async throws {
        try await CSSearchableIndex(name: indexName).deleteAllSearchableItems()
    }
}
