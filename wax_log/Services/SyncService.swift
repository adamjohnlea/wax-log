import Foundation
@preconcurrency import CoreData

@Observable
final class SyncService {
    private let persistenceController: PersistenceController
    private let discogsClient = DiscogsClient.shared

    // Progress tracking
    var isSyncing = false
    var syncProgress: SyncProgress?
    var lastError: String?

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Initial Sync

    func performInitialSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        syncProgress = SyncProgress(phase: .fetchingCollection, current: 0, total: 0, message: "Starting sync...")

        do {
            guard let username = KeychainService.load(.discogsUsername), !username.isEmpty else {
                throw SyncError.noUsername
            }

            // Phase 1: Sync collection
            try await syncCollection(username: username)

            // Phase 2: Sync wantlist
            try await syncWantlist(username: username)

            syncProgress = SyncProgress(phase: .complete, current: 0, total: 0, message: "Sync complete!")
            UserDefaults.standard.set(Date(), forKey: "lastSyncDate")
        } catch {
            lastError = error.localizedDescription
            syncProgress = SyncProgress(phase: .error, current: 0, total: 0, message: error.localizedDescription)
        }

        isSyncing = false
    }

    // MARK: - Incremental Refresh

    func performIncrementalRefresh() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        syncProgress = SyncProgress(phase: .fetchingCollection, current: 0, total: 0, message: "Checking for updates...")

        do {
            guard let username = KeychainService.load(.discogsUsername), !username.isEmpty else {
                throw SyncError.noUsername
            }

            try await syncCollection(username: username)
            try await syncWantlist(username: username)

            syncProgress = SyncProgress(phase: .complete, current: 0, total: 0, message: "Refresh complete!")
            UserDefaults.standard.set(Date(), forKey: "lastSyncDate")
        } catch {
            lastError = error.localizedDescription
            syncProgress = SyncProgress(phase: .error, current: 0, total: 0, message: error.localizedDescription)
        }

        isSyncing = false
    }

    // MARK: - Collection Sync

    private func syncCollection(username: String) async throws {
        var page = 1
        var totalItems = 0
        var processedItems = 0

        // Fetch first page to get total count
        let firstPage = try await discogsClient.getCollectionReleases(username: username, page: 1)
        totalItems = firstPage.pagination.items
        let totalPages = firstPage.pagination.pages

        syncProgress = SyncProgress(phase: .fetchingCollection, current: 0, total: totalItems, message: "Syncing collection...")

        try await processCollectionReleases(firstPage.items, processedSoFar: &processedItems, total: totalItems)
        page = 2

        while page <= totalPages {
            let response = try await discogsClient.getCollectionReleases(username: username, page: page)
            try await processCollectionReleases(response.items, processedSoFar: &processedItems, total: totalItems)
            page += 1
        }
    }

    private func processCollectionReleases(_ releases: [CollectionRelease], processedSoFar: inout Int, total: Int) async throws {
        let context = persistenceController.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        try await context.perform {
            for item in releases {
                let info = item.basicInformation
                let release = self.fetchOrCreateRelease(discogsId: Int64(info.id), listType: "collection", in: context)

                release.title = info.title
                release.artist = info.artists?.map(\.name).joined(separator: ", ") ?? ""
                release.year = Int32(info.year)
                release.label = info.labels?.first?.name ?? ""
                release.format = info.formats?.first?.name ?? ""
                release.genre = info.genres?.joined(separator: ", ") ?? ""
                release.style = info.styles?.joined(separator: ", ") ?? ""
                release.imageURL = info.coverImage
                release.rating = Int16(item.rating)
                release.listType = "collection"

                release.dateAdded = self.parseDiscogsDate(item.dateAdded) ?? release.dateAdded ?? Date()

                // Extract media/sleeve condition from notes fields
                if let notes = item.notes {
                    for note in notes {
                        switch note.fieldId {
                        case 1: release.mediaCondition = note.value
                        case 2: release.sleeveCondition = note.value
                        case 3: release.personalNotes = note.value
                        default: break
                        }
                    }
                }
            }

            if context.hasChanges {
                try context.save()
            }
        }

        processedSoFar += releases.count
        syncProgress = SyncProgress(phase: .fetchingCollection, current: processedSoFar, total: total, message: "Syncing collection... \(processedSoFar)/\(total)")
    }

    // MARK: - Wantlist Sync

    private func syncWantlist(username: String) async throws {
        var page = 1
        var totalItems = 0
        var processedItems = 0

        let firstPage = try await discogsClient.getWantlistReleases(username: username, page: 1)
        totalItems = firstPage.pagination.items
        let totalPages = firstPage.pagination.pages

        syncProgress = SyncProgress(phase: .fetchingWantlist, current: 0, total: totalItems, message: "Syncing wantlist...")

        try await processWantlistReleases(firstPage.items, processedSoFar: &processedItems, total: totalItems)
        page = 2

        while page <= totalPages {
            let response = try await discogsClient.getWantlistReleases(username: username, page: page)
            try await processWantlistReleases(response.items, processedSoFar: &processedItems, total: totalItems)
            page += 1
        }
    }

    private func processWantlistReleases(_ releases: [WantlistRelease], processedSoFar: inout Int, total: Int) async throws {
        let context = persistenceController.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        try await context.perform {
            for item in releases {
                let info = item.basicInformation
                let release = self.fetchOrCreateRelease(discogsId: Int64(info.id), listType: "wantlist", in: context)

                release.title = info.title
                release.artist = info.artists?.map(\.name).joined(separator: ", ") ?? ""
                release.year = Int32(info.year)
                release.label = info.labels?.first?.name ?? ""
                release.format = info.formats?.first?.name ?? ""
                release.genre = info.genres?.joined(separator: ", ") ?? ""
                release.style = info.styles?.joined(separator: ", ") ?? ""
                release.imageURL = info.coverImage
                release.rating = Int16(item.rating)
                release.listType = "wantlist"
                release.personalNotes = item.notes

                release.dateAdded = self.parseDiscogsDate(item.dateAdded) ?? release.dateAdded ?? Date()
            }

            if context.hasChanges {
                try context.save()
            }
        }

        processedSoFar += releases.count
        syncProgress = SyncProgress(phase: .fetchingWantlist, current: processedSoFar, total: total, message: "Syncing wantlist... \(processedSoFar)/\(total)")
    }

    // MARK: - Enrichment

    func enrichAllReleases() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil

        do {
            let context = persistenceController.container.newBackgroundContext()
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            // Fetch all unenriched releases
            let request = NSFetchRequest<Release>(entityName: "Release")
            request.predicate = NSPredicate(format: "enriched == NO")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)]

            let unenriched = try await context.perform { try context.fetch(request) }
            let total = unenriched.count

            guard total > 0 else {
                syncProgress = SyncProgress(phase: .complete, current: 0, total: 0, message: "All releases already enriched!")
                isSyncing = false
                return
            }

            syncProgress = SyncProgress(phase: .enriching, current: 0, total: total, message: "Enriching releases...")

            for (index, release) in unenriched.enumerated() {
                nonisolated(unsafe) let release = release
                let discogsId = await context.perform { Int(release.discogsId) }

                do {
                    let detail = try await discogsClient.getReleaseDetail(releaseId: discogsId)

                    await context.perform {
                        // Tracklist
                        if let tracks = detail.tracklist {
                            let trackData: [[String: String]] = tracks.compactMap { track in
                                guard track.type == nil || track.type == "track" else { return nil }
                                return [
                                    "position": track.position ?? "",
                                    "title": track.title,
                                    "duration": track.duration ?? ""
                                ]
                            }
                            if let json = try? JSONSerialization.data(withJSONObject: trackData),
                               let jsonString = String(data: json, encoding: .utf8) {
                                release.tracklist = jsonString
                            }
                        }

                        // Credits
                        if let extraartists = detail.extraartists {
                            let creditData: [[String: String]] = extraartists.map { artist in
                                ["name": artist.name, "role": artist.role ?? ""]
                            }
                            if let json = try? JSONSerialization.data(withJSONObject: creditData),
                               let jsonString = String(data: json, encoding: .utf8) {
                                release.credits = jsonString
                            }
                        }

                        // Identifiers
                        if let ids = detail.identifiers {
                            let idData: [[String: String]] = ids.compactMap { id in
                                guard let type = id.type, let value = id.value else { return nil }
                                return ["type": type, "value": value]
                            }
                            if let json = try? JSONSerialization.data(withJSONObject: idData),
                               let jsonString = String(data: json, encoding: .utf8) {
                                release.identifiers = jsonString
                            }

                            // Extract barcode from identifiers
                            if release.barcode == nil || release.barcode?.isEmpty == true {
                                let barcode = ids.first(where: { $0.type == "Barcode" })?.value
                                release.barcode = barcode
                            }
                        }

                        // Country & notes from full release
                        if let country = detail.country, !country.isEmpty {
                            release.country = country
                        }
                        if let notes = detail.notes, !notes.isEmpty {
                            release.notes = notes
                        }

                        // Prefer primary image URL
                        if let primaryImage = detail.images?.first(where: { $0.type == "primary" }) {
                            release.imageURL = primaryImage.uri
                        }

                        // Store all non-primary images
                        if let images = detail.images {
                            let additional = images.filter { $0.type != "primary" }
                            if !additional.isEmpty {
                                let imageData: [[String: Any]] = additional.map { img in
                                    ["type": img.type, "uri": img.uri, "uri150": img.uri150, "width": img.width, "height": img.height]
                                }
                                if let json = try? JSONSerialization.data(withJSONObject: imageData),
                                   let jsonString = String(data: json, encoding: .utf8) {
                                    release.additionalImages = jsonString
                                }
                            }
                        }

                        release.enriched = true

                        try? context.save()
                    }
                } catch {
                    // Skip individual failures, continue with next release
                }

                syncProgress = SyncProgress(phase: .enriching, current: index + 1, total: total, message: "Enriching releases... \(index + 1)/\(total)")
            }

            syncProgress = SyncProgress(phase: .complete, current: total, total: total, message: "Enrichment complete!")
        } catch {
            lastError = error.localizedDescription
            syncProgress = SyncProgress(phase: .error, current: 0, total: 0, message: error.localizedDescription)
        }

        isSyncing = false
    }

    func enrichSingleRelease(_ objectID: NSManagedObjectID) async {
        let context = persistenceController.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        guard let fetchedRelease = try? await context.perform({ try context.existingObject(with: objectID) as? Release }) else { return }
        nonisolated(unsafe) let release = fetchedRelease

        let discogsId = await context.perform { Int(release.discogsId) }

        do {
            let detail = try await discogsClient.getReleaseDetail(releaseId: discogsId)

            await context.perform {
                if let tracks = detail.tracklist {
                    let trackData: [[String: String]] = tracks.compactMap { track in
                        guard track.type == nil || track.type == "track" else { return nil }
                        return [
                            "position": track.position ?? "",
                            "title": track.title,
                            "duration": track.duration ?? ""
                        ]
                    }
                    if let json = try? JSONSerialization.data(withJSONObject: trackData),
                       let jsonString = String(data: json, encoding: .utf8) {
                        release.tracklist = jsonString
                    }
                }

                if let extraartists = detail.extraartists {
                    let creditData: [[String: String]] = extraartists.map { artist in
                        ["name": artist.name, "role": artist.role ?? ""]
                    }
                    if let json = try? JSONSerialization.data(withJSONObject: creditData),
                       let jsonString = String(data: json, encoding: .utf8) {
                        release.credits = jsonString
                    }
                }

                if let ids = detail.identifiers {
                    let idData: [[String: String]] = ids.compactMap { id in
                        guard let type = id.type, let value = id.value else { return nil }
                        return ["type": type, "value": value]
                    }
                    if let json = try? JSONSerialization.data(withJSONObject: idData),
                       let jsonString = String(data: json, encoding: .utf8) {
                        release.identifiers = jsonString
                    }

                    if release.barcode == nil || release.barcode?.isEmpty == true {
                        let barcode = ids.first(where: { $0.type == "Barcode" })?.value
                        release.barcode = barcode
                    }
                }

                if let country = detail.country, !country.isEmpty {
                    release.country = country
                }
                if let notes = detail.notes, !notes.isEmpty {
                    release.notes = notes
                }

                if let primaryImage = detail.images?.first(where: { $0.type == "primary" }) {
                    release.imageURL = primaryImage.uri
                }

                if let images = detail.images {
                    let additional = images.filter { $0.type != "primary" }
                    if !additional.isEmpty {
                        let imageData: [[String: Any]] = additional.map { img in
                            ["type": img.type, "uri": img.uri, "uri150": img.uri150, "width": img.width, "height": img.height]
                        }
                        if let json = try? JSONSerialization.data(withJSONObject: imageData),
                           let jsonString = String(data: json, encoding: .utf8) {
                            release.additionalImages = jsonString
                        }
                    }
                }

                release.enriched = true
                try? context.save()
            }
        } catch {
            // Silently fail for single enrichment
        }
    }

    // MARK: - Image Backfill

    func backfillAllImages() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil

        let context = persistenceController.container.viewContext
        let request = NSFetchRequest<Release>(entityName: "Release")
        request.predicate = NSPredicate(format: "enriched == YES AND additionalImages != nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)]

        do {
            let releases = try context.fetch(request)
            var totalImages = 0
            var downloaded = 0

            // Count total images to download
            for release in releases {
                if let images = release.decodedAdditionalImages {
                    for (index, _) in images.enumerated() {
                        if await !ImageCacheService.shared.hasAdditionalImage(discogsId: release.discogsId, imageIndex: index) {
                            totalImages += 1
                        }
                    }
                }
            }

            guard totalImages > 0 else {
                syncProgress = SyncProgress(phase: .complete, current: 0, total: 0, message: "All artwork already downloaded!")
                isSyncing = false
                return
            }

            syncProgress = SyncProgress(phase: .backfillingImages, current: 0, total: totalImages, message: "Downloading artwork...")

            for release in releases {
                guard let images = release.decodedAdditionalImages else { continue }
                let discogsId = release.discogsId

                for (index, image) in images.enumerated() {
                    if await ImageCacheService.shared.hasAdditionalImage(discogsId: discogsId, imageIndex: index) {
                        continue
                    }

                    guard await ImageCacheService.shared.remainingDailyDownloads > 0 else {
                        syncProgress = SyncProgress(phase: .complete, current: downloaded, total: totalImages, message: "Daily image limit reached. \(downloaded) downloaded.")
                        isSyncing = false
                        return
                    }

                    if let url = URL(string: image.uri) {
                        _ = await ImageCacheService.shared.downloadAdditionalImage(discogsId: discogsId, imageIndex: index, url: url)
                    }

                    downloaded += 1
                    syncProgress = SyncProgress(phase: .backfillingImages, current: downloaded, total: totalImages, message: "Downloading artwork... \(downloaded)/\(totalImages)")
                }
            }

            syncProgress = SyncProgress(phase: .complete, current: downloaded, total: totalImages, message: "Artwork download complete! \(downloaded) images.")
        } catch {
            lastError = error.localizedDescription
            syncProgress = SyncProgress(phase: .error, current: 0, total: 0, message: error.localizedDescription)
        }

        isSyncing = false
    }

    // MARK: - Push to Discogs

    /// Push local edits (rating, condition, notes) for a single release back to Discogs.
    func pushReleaseToDiscogs(_ objectID: NSManagedObjectID) async throws {
        guard let username = KeychainService.load(.discogsUsername), !username.isEmpty else {
            throw SyncError.noUsername
        }

        let context = persistenceController.container.viewContext
        guard let release = try? context.existingObject(with: objectID) as? Release else { return }
        guard release.isCollection else { return } // Can only edit collection items

        let discogsId = Int(release.discogsId)
        let rating = Int(release.rating)
        let mediaCondition = release.mediaCondition ?? ""
        let sleeveCondition = release.sleeveCondition ?? ""
        let personalNotes = release.personalNotes ?? ""

        // Push rating
        try await discogsClient.setRating(username: username, releaseId: discogsId, rating: rating)

        // Need instance_id to edit fields — fetch it
        let instances = try await discogsClient.getCollectionInstances(username: username, releaseId: discogsId)
        guard let instance = instances.items.first else { return }
        let instanceId = instance.instanceId

        // Push media condition (field 1)
        if !mediaCondition.isEmpty {
            try await discogsClient.editInstanceField(
                username: username, releaseId: discogsId, instanceId: instanceId,
                fieldId: 1, value: mediaCondition
            )
        }

        // Push sleeve condition (field 2)
        if !sleeveCondition.isEmpty {
            try await discogsClient.editInstanceField(
                username: username, releaseId: discogsId, instanceId: instanceId,
                fieldId: 2, value: sleeveCondition
            )
        }

        // Push personal notes (field 3)
        try await discogsClient.editInstanceField(
            username: username, releaseId: discogsId, instanceId: instanceId,
            fieldId: 3, value: personalNotes
        )
    }

    // MARK: - Helpers

    private func fetchOrCreateRelease(discogsId: Int64, listType: String, in context: NSManagedObjectContext) -> Release {
        let request = NSFetchRequest<Release>(entityName: "Release")
        request.predicate = NSPredicate(format: "discogsId == %lld AND listType == %@", discogsId, listType)
        request.fetchLimit = 1

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let release = Release(context: context)
        release.discogsId = discogsId
        release.listType = listType
        release.enriched = false
        release.country = ""
        return release
    }

    private func parseDiscogsDate(_ dateString: String) -> Date? {
        // Discogs format: "2022-05-01T12:29:03-07:00"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Try with fractional seconds
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString)
    }

    var lastSyncDate: Date? {
        UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }
}

// MARK: - Progress Model

struct SyncProgress {
    enum Phase {
        case fetchingCollection
        case fetchingWantlist
        case enriching
        case backfillingImages
        case complete
        case error
    }

    let phase: Phase
    let current: Int
    let total: Int
    let message: String

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

// MARK: - Errors

nonisolated enum SyncError: LocalizedError {
    case noUsername

    var errorDescription: String? {
        switch self {
        case .noUsername:
            return "No Discogs username configured. Add your username in Settings."
        }
    }
}
