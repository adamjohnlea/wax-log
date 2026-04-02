import SwiftUI
import CoreData

struct ToolsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var syncService = SyncService()
    @State private var showingResetConfirmation = false

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
            Button("Delete Everything", role: .destructive) {
                resetAllData()
            }
        } message: {
            Text("This will delete all local releases, smart collections, and cached images. Your Discogs account is not affected. This cannot be undone.")
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
                        Task {
                            try? await ImageCacheService.shared.clearCache()
                        }
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
                    Text("Delete all local releases, smart collections, and cached images.")
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

    private func resetAllData() {
        let context = viewContext

        // Delete all releases
        let releaseRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Release")
        let releaseDelete = NSBatchDeleteRequest(fetchRequest: releaseRequest)
        _ = try? context.execute(releaseDelete)

        // Delete all smart collections
        let scRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "SmartCollection")
        let scDelete = NSBatchDeleteRequest(fetchRequest: scRequest)
        _ = try? context.execute(scDelete)

        // Clear image cache
        Task { try? await ImageCacheService.shared.clearCache() }

        // Reset sync state
        UserDefaults.standard.removeObject(forKey: "lastSyncDate")
        UserDefaults.standard.removeObject(forKey: "imageDailyCount")
        UserDefaults.standard.removeObject(forKey: "imageDailyResetDate")

        // Refresh context
        context.reset()
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
