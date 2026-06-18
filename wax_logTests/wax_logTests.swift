import Testing
import CoreData
@testable import Vinyl_Crate

/// Shared helpers for building an isolated, CloudKit-free in-memory Core Data
/// stack in tests, plus convenient `Release` factories.
@MainActor
enum TestStore {
    /// A fresh in-memory context backed by the app's Core Data model (no CloudKit).
    static func makeContext() -> NSManagedObjectContext {
        let container = NSPersistentContainer(name: "WaxLog")
        let description = container.persistentStoreDescriptions.first!
        description.url = URL(fileURLWithPath: "/dev/null")
        container.loadPersistentStores { _, error in
            precondition(error == nil, "Failed to load in-memory store: \(String(describing: error))")
        }
        return container.viewContext
    }

    @discardableResult
    static func makeRelease(
        in context: NSManagedObjectContext,
        discogsId: Int64 = 1,
        title: String = "Untitled",
        artist: String = "Artist",
        year: Int32 = 0,
        genre: String = "",
        style: String = "",
        label: String = "",
        country: String = "",
        format: String = "",
        rating: Int16 = 0,
        listType: String = "collection"
    ) -> Release {
        let release = Release(context: context)
        release.discogsId = discogsId
        release.title = title
        release.artist = artist
        release.year = year
        release.genre = genre
        release.style = style
        release.label = label
        release.country = country
        release.format = format
        release.rating = rating
        release.listType = listType
        release.enriched = false
        return release
    }
}

@MainActor
struct PersistenceSmokeTests {
    @Test func inMemoryStoreSavesAndFetches() throws {
        let context = TestStore.makeContext()
        _ = TestStore.makeRelease(in: context, discogsId: 1, listType: "collection")
        try context.save()

        let count = try context.count(for: Release.collectionFetchRequest())
        #expect(count == 1)
    }
}
