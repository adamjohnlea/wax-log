import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "WaxLog")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store descriptions found")
        }

        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.waxlog")
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Core Data store failed to load: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        for i in 0..<10 {
            let release = Release(context: context)
            release.discogsId = Int64(i + 1)
            release.title = "Sample Album \(i + 1)"
            release.artist = "Sample Artist \(i + 1)"
            release.year = Int32(1970 + i)
            release.label = "Sample Label"
            release.format = "Vinyl"
            release.genre = "Rock"
            release.style = "Classic Rock"
            release.country = "US"
            release.listType = "collection"
            release.dateAdded = Date()
            release.enriched = false
            release.rating = Int16(i % 6)
        }

        do {
            try context.save()
        } catch {
            fatalError("Preview Core Data save error: \(error.localizedDescription)")
        }

        return controller
    }()
}
