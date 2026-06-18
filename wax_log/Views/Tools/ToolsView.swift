import SwiftUI
import CoreData
import CoreSpotlight

struct ToolsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var syncService = SyncService()
    @State private var showingResetConfirmation = false
    @State private var showingClearCacheConfirmation = false
    @State private var toolsError: String?

    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "listType == %@", "collection"))
    private var collectionReleases: FetchedResults<Release>

    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "listType == %@", "wantlist"))
    private var wantlistReleases: FetchedResults<Release>

    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "enriched == YES"))
    private var enrichedReleases: FetchedResults<Release>

    @FetchRequest(sortDescriptors: [])
    private var allReleases: FetchedResults<Release>

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Sync status
                syncStatusSection

                // Sync actions
                syncActionsSection

                // Artwork backfill
                artworkBackfillSection

                // Image cache
                imageCacheSection

                // Maintenance
                maintenanceSection

                // Database info
                databaseSection

                // Danger zone
                dangerZoneSection
            }
            .padding()
        }
        .navigationTitle("Tools")
        .onAppear { updateCacheSize() }
        .alert("Reset All Data", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everywhere", role: .destructive) {
                resetAllData()
            }
        } message: {
            Text("This deletes all releases, smart collections, and cached images from this Mac and iCloud — removing them from all your devices. Your Discogs account is not affected, so you can re-sync. This cannot be undone.")
        }
        .alert("Clear Image Cache", isPresented: $showingClearCacheConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { clearImageCache() }
        } message: {
            Text("This deletes all locally cached cover art. Images will be re-downloaded from Discogs as needed.")
        }
        .alert(
            "Operation Failed",
            isPresented: Binding(get: { toolsError != nil }, set: { if !$0 { toolsError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(toolsError ?? "")
        }
    }

    // MARK: - Sync Status

    private var syncStatusSection: some View {
        GroupBox("Sync Status") {
            VStack(alignment: .leading, spacing: 12) {
                if let progress = syncService.syncProgress {
                    SyncProgressView(progress: progress)
                } else {
                    HStack {
                        Image(systemName: lastSyncIcon)
                            .foregroundStyle(lastSyncColor)
                        Text(lastSyncText)
                            .font(.callout)
                        Spacer()
                    }
                }

                if let error = syncService.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var lastSyncText: String {
        if let date = syncService.lastSyncDate {
            return "Last sync: \(date.formatted(.relative(presentation: .named)))"
        }
        return "Never synced"
    }

    private var lastSyncIcon: String {
        syncService.lastSyncDate != nil ? "checkmark.circle" : "questionmark.circle"
    }

    private var lastSyncColor: Color {
        syncService.lastSyncDate != nil ? .green : .secondary
    }

    // MARK: - Sync Actions

    private var syncActionsSection: some View {
        GroupBox("Sync Actions") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Initial Sync")
                            .font(.callout.weight(.medium))
                        Text("Download your full collection and wantlist from Discogs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sync Now") {
                        Task { await syncService.performInitialSync() }
                    }
                    .disabled(syncService.isSyncing)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        Text("Refresh")
                            .font(.callout.weight(.medium))
                        Text("Check for new or updated releases.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh") {
                        Task { await syncService.performIncrementalRefresh() }
                    }
                    .disabled(syncService.isSyncing)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        Text("Enrich All")
                            .font(.callout.weight(.medium))
                        Text("Fetch full details (tracklist, credits, identifiers) for all releases. \(unenrichedCount) unenriched.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Enrich") {
                        Task { await syncService.enrichAllReleases() }
                    }
                    .disabled(syncService.isSyncing || unenrichedCount == 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var unenrichedCount: Int {
        allReleases.count - enrichedReleases.count
    }

    // MARK: - Artwork Backfill

    private var artworkBackfillSection: some View {
        GroupBox("Artwork Backfill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Download Additional Artwork")
                            .font(.callout.weight(.medium))
                        Text("Download back covers, inserts, and other images for enriched releases. Respects the 1000/day Discogs limit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Backfill All") {
                        Task { await syncService.backfillAllImages() }
                    }
                    .disabled(syncService.isSyncing || enrichedReleases.isEmpty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Image Cache

    private var imageCacheSection: some View {
        GroupBox("Image Cache") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Cached Images")
                            .font(.callout.weight(.medium))
                        Text("Cover art stored locally for offline browsing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(cacheSizeFormatted)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Daily downloads: \(dailyDownloadCount)/1000")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear Cache") {
                        showingClearCacheConfirmation = true
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @State private var cacheSizeFormatted: String = "—"

    private func updateCacheSize() {
        Task {
            let bytes = await ImageCacheService.shared.cacheSize
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            cacheSizeFormatted = formatter.string(fromByteCount: bytes)
        }
    }

    private var dailyDownloadCount: Int {
        UserDefaults.standard.integer(forKey: "imageDailyCount")
    }

    // MARK: - Maintenance

    private var maintenanceSection: some View {
        GroupBox("Maintenance") {
            HStack {
                VStack(alignment: .leading) {
                    Text("Deduplicate Releases")
                        .font(.callout.weight(.medium))
                    Text("Remove duplicate records caused by iCloud sync conflicts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Deduplicate") {
                    let count = syncService.deduplicateReleases()
                    dedupMessage = count > 0 ? "Removed \(count) duplicate\(count == 1 ? "" : "s")." : "No duplicates found."
                }

                if let msg = dedupMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @State private var dedupMessage: String?

    // MARK: - Database

    private var databaseSection: some View {
        GroupBox("Database") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Collection").foregroundStyle(.secondary)
                    Text("\(collectionReleases.count) releases")
                }
                GridRow {
                    Text("Wantlist").foregroundStyle(.secondary)
                    Text("\(wantlistReleases.count) releases")
                }
                GridRow {
                    Text("Enriched").foregroundStyle(.secondary)
                    Text("\(enrichedReleases.count) of \(allReleases.count)")
                }
                GridRow {
                    Text("iCloud Sync").foregroundStyle(.secondary)
                    Text("Automatic")
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Danger Zone

    private var dangerZoneSection: some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading) {
                    Text("Reset All Data")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.red)
                    Text("Delete all releases, smart collections, and cached images from this Mac and iCloud (all devices).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset", role: .destructive) {
                    showingResetConfirmation = true
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Danger Zone", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Actions

    private func clearImageCache() {
        Task {
            do {
                try await ImageCacheService.shared.clearCache()
                updateCacheSize()
            } catch {
                toolsError = error.localizedDescription
            }
        }
    }

    private func resetAllData() {
        let context = viewContext

        // Delete through the context (not NSBatchDeleteRequest) so the deletions are
        // recorded in persistent history and exported to CloudKit — removing the data
        // from iCloud and every synced device, instead of letting it sync back.
        do {
            let releaseRequest = NSFetchRequest<Release>(entityName: "Release")
            for release in try context.fetch(releaseRequest) {
                context.delete(release)
            }

            let scRequest = NSFetchRequest<SmartCollection>(entityName: "SmartCollection")
            for collection in try context.fetch(scRequest) {
                context.delete(collection)
            }

            try context.save()
        } catch {
            toolsError = "Failed to reset data: \(error.localizedDescription)"
            return
        }

        // Clear image cache and the Spotlight index
        Task {
            try? await CSSearchableIndex(name: AppModel.spotlightIndexName).deleteAllSearchableItems()
            do {
                try await ImageCacheService.shared.clearCache()
                updateCacheSize()
            } catch {
                toolsError = "Data was reset, but clearing the image cache failed: \(error.localizedDescription)"
            }
        }

        // Reset sync state
        UserDefaults.standard.removeObject(forKey: "lastSyncDate")
        UserDefaults.standard.removeObject(forKey: "imageDailyCount")
        UserDefaults.standard.removeObject(forKey: "imageDailyResetDate")
    }
}

// MARK: - Sync Progress View

struct SyncProgressView: View {
    let progress: SyncProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                switch progress.phase {
                case .fetchingCollection:
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.blue)
                case .fetchingWantlist:
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.purple)
                case .enriching:
                    Image(systemName: "sparkles")
                        .foregroundStyle(.orange)
                case .backfillingImages:
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundStyle(.teal)
                case .complete:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .error:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                Text(progress.message)
                    .font(.callout)

                Spacer()

                if progress.phase != .complete && progress.phase != .error {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if progress.total > 0 && progress.phase != .complete {
                ProgressView(value: progress.fraction)
                    .tint(progressTint)

                Text("\(progress.current) of \(progress.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressTint: Color {
        switch progress.phase {
        case .fetchingCollection: .blue
        case .backfillingImages: .teal
        case .fetchingWantlist: .purple
        case .enriching: .orange
        case .complete: .green
        case .error: .red
        }
    }
}
