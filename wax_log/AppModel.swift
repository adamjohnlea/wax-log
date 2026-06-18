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

    /// Donates the full collection + wantlist to Spotlight so records are
    /// findable in search and can open via `OpenReleaseIntent`. Replaces the
    /// index (rather than only adding) so records removed from the collection
    /// don't linger as stale search results. Best-effort.
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
        } catch {
            // Spotlight indexing is best-effort; a failure shouldn't disrupt the app.
        }
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
