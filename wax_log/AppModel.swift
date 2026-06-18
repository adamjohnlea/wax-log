import SwiftUI
import CoreData
import CoreSpotlight
import AppIntents

/// App-wide navigation and action state.
///
/// A single instance is created in `wax_logApp`, injected into the SwiftUI
/// environment for the view layer, and registered with `AppDependencyManager`
/// so App Intents (which run outside the view tree) can drive the same
/// navigation — for example, opening a release or picking a random album.
///
/// Mutate this from the main actor only (SwiftUI views and `@MainActor` intent
/// `perform()` methods).
@Observable
final class AppModel {
    /// The currently selected sidebar section, shown in the content column.
    var selectedSection: SidebarSection? = .collection

    /// The release shown in the detail column, or `nil` for the empty state.
    var selectedRelease: NSManagedObjectID?

    /// Drives Discogs sync, refresh, and enrichment. Owned here so menu
    /// commands and App Intents share one instance and its progress state.
    let syncService: SyncService

    private let persistenceController: PersistenceController
    private let savedSectionKey = "selectedSection"
    private let spotlightSeededKey = "spotlightSeeded"

    /// Named Spotlight index for the collection (a named index is recommended
    /// over the default for app content).
    static let spotlightIndexName = "VinylCrateReleases"

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
        self.syncService = SyncService(persistenceController: persistenceController)
    }

    // MARK: - Navigation

    /// Restores the last static section on launch. Smart-collection selections
    /// aren't restorable from a raw string (their identity is an object ID), so
    /// unknown values fall back to the default section.
    func restoreSavedSection() {
        if let raw = UserDefaults.standard.string(forKey: savedSectionKey),
           let section = SidebarSection(rawValue: raw) {
            selectedSection = section
        }
    }

    /// Handles a user picking a section in the sidebar: switch section, clear
    /// the detail selection, and persist. Programmatic navigation (e.g.
    /// `openRelease`) deliberately sets the section *without* going through here,
    /// so it can set a section and a release together without one clearing the other.
    func selectSection(_ section: SidebarSection?) {
        selectedSection = section
        selectedRelease = nil
        UserDefaults.standard.set(section?.rawValue ?? "collection", forKey: savedSectionKey)
    }

    // MARK: - Sync actions (menu commands + intents)

    func syncCollection() {
        Task {
            await syncService.performInitialSync()
            await indexCollection()
        }
    }

    func refreshCollection() {
        Task {
            await syncService.performIncrementalRefresh()
            await indexCollection()
        }
    }

    func enrichAll() {
        Task { await syncService.enrichAllReleases() }
    }

    // MARK: - App Intents support

    /// Navigates to a specific release. Called by `OpenReleaseIntent` (including
    /// Spotlight-launched opens).
    func openRelease(discogsId: Int64, listType: String) {
        let context = persistenceController.container.viewContext
        let request = NSFetchRequest<Release>(entityName: "Release")
        request.predicate = NSPredicate(format: "discogsId == %lld AND listType == %@", discogsId, listType)
        request.fetchLimit = 1
        guard let release = try? context.fetch(request).first else { return }

        selectedSection = listType == "wantlist" ? .wantlist : .collection
        selectedRelease = release.objectID
        UserDefaults.standard.set(selectedSection?.rawValue ?? "collection", forKey: savedSectionKey)
    }

    /// Searches Discogs for `query` and adds the top match to the wantlist,
    /// re-indexing so it's searchable. Returns the added title, or `nil` if
    /// nothing matched.
    func addToWantlist(matching query: String) async throws -> String? {
        guard let result = try await syncService.addTopMatch(query: query, listType: "wantlist") else {
            return nil
        }
        await indexRelease(discogsId: Int64(result.id), listType: "wantlist")
        return result.title
    }

    /// Seeds the Spotlight index once per install, for data synced before
    /// indexing existed. After that, incremental add/remove plus the full
    /// reconcile on each sync keep it current — so we don't re-index the whole
    /// collection on every launch.
    func indexCollectionIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: spotlightSeededKey) else { return }
        await indexCollection()
    }

    /// Donates the full collection + wantlist to Spotlight, replacing the index
    /// so records removed elsewhere don't linger as stale results. Run after a
    /// sync, where the whole dataset may have changed. Best-effort.
    func indexCollection() async {
        let context = persistenceController.container.newBackgroundContext()
        let entities: [ReleaseEntity] = await context.perform {
            let request = NSFetchRequest<Release>(entityName: "Release")
            let releases = (try? context.fetch(request)) ?? []
            return releases.map(ReleaseEntity.init(release:))
        }
        let index = CSSearchableIndex(name: Self.spotlightIndexName)
        do {
            try await index.deleteAllSearchableItems()
            if !entities.isEmpty {
                try await index.indexAppEntities(entities)
            }
            UserDefaults.standard.set(true, forKey: spotlightSeededKey)
        } catch {
            // Spotlight indexing is best-effort; a failure shouldn't disrupt the app.
        }
    }

    /// Adds or updates a single release in the Spotlight index.
    func indexRelease(discogsId: Int64, listType: String) async {
        let context = persistenceController.container.newBackgroundContext()
        let entity: ReleaseEntity? = await context.perform {
            let request = NSFetchRequest<Release>(entityName: "Release")
            request.predicate = NSPredicate(format: "discogsId == %lld AND listType == %@", discogsId, listType)
            request.fetchLimit = 1
            return (try? context.fetch(request).first).map(ReleaseEntity.init(release:))
        }
        guard let entity else { return }
        try? await CSSearchableIndex(name: Self.spotlightIndexName).indexAppEntities([entity])
    }

    /// Removes a single release from the Spotlight index.
    func deindexRelease(discogsId: Int64, listType: String) async {
        let id = "\(discogsId)-\(listType)"
        try? await CSSearchableIndex(name: Self.spotlightIndexName)
            .deleteAppEntities(identifiedBy: [id], ofType: ReleaseEntity.self)
    }

    // MARK: - Randomizer

    /// Picks a random release from the collection, navigates to it, and returns
    /// its title (for intent dialog). Returns `nil` if the collection is empty.
    @discardableResult
    func surpriseMe() -> String? {
        let context = persistenceController.container.viewContext
        guard let releases = try? context.fetch(Release.collectionFetchRequest()),
              let pick = releases.randomElement() else {
            return nil
        }
        selectedSection = .collection
        selectedRelease = pick.objectID
        UserDefaults.standard.set(SidebarSection.collection.rawValue, forKey: savedSectionKey)
        return pick.title
    }
}
