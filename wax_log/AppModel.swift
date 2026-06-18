import SwiftUI
import CoreData

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

    /// Call when the section changes: clear the detail selection and persist the
    /// new section. Does not reassign `selectedSection`, so it's safe to call
    /// from `.onChange(of: selectedSection)` without recursing.
    func sectionDidChange() {
        selectedRelease = nil
        UserDefaults.standard.set(selectedSection?.rawValue ?? "collection", forKey: savedSectionKey)
    }

    // MARK: - Sync actions (menu commands + intents)

    func syncCollection() {
        Task { await syncService.performInitialSync() }
    }

    func refreshCollection() {
        Task { await syncService.performIncrementalRefresh() }
    }

    func enrichAll() {
        Task { await syncService.enrichAllReleases() }
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
