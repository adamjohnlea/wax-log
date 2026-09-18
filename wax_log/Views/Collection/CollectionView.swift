import SwiftUI
import CoreData

struct CollectionView: View {
    let listType: String
    @Binding var selectedRelease: NSManagedObjectID?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppModel.self) private var appModel
    @AppStorage("sortOrder") private var sortOrderRaw: String = "dateAdded"
    @AppStorage("viewMode") private var viewModeRaw: String = "list"
    @State private var searchText = ""
    @State private var releaseToDelete: Release?
    @State private var actionError: String?

    private var sortOrder: SortOrder {
        SortOrder(rawValue: sortOrderRaw) ?? .dateAdded
    }

    private var viewMode: ViewMode {
        ViewMode(rawValue: viewModeRaw) ?? .list
    }

    @FetchRequest private var releases: FetchedResults<Release>

    init(listType: String, selectedRelease: Binding<NSManagedObjectID?>) {
        self.listType = listType
        self._selectedRelease = selectedRelease

        // Persist sort order and view mode per list so Collection and Wantlist stay independent.
        _sortOrderRaw = AppStorage(wrappedValue: SortOrder.dateAdded.rawValue, "sortOrder_\(listType)")
        _viewModeRaw = AppStorage(wrappedValue: ViewMode.list.rawValue, "viewMode_\(listType)")

        // Seed the fetch request with the persisted sort order so the saved order
        // applies on first render — .onChange does not fire on initial appearance.
        let savedSort = UserDefaults.standard.string(forKey: "sortOrder_\(listType)")
        let initialSort = SortOrder(rawValue: savedSort ?? "") ?? .dateAdded
        _releases = FetchRequest(
            sortDescriptors: initialSort.descriptors,
            predicate: NSPredicate(format: "listType == %@", listType),
            animation: .default
        )
    }

    private var filteredReleases: [Release] {
        guard !searchText.isEmpty else { return Array(releases) }
        let query = searchText.lowercased()
        return releases.filter { release in
            (release.artist ?? "").lowercased().contains(query) ||
            (release.title ?? "").lowercased().contains(query)
        }
    }

    var body: some View {
        Group {
            if filteredReleases.isEmpty && searchText.isEmpty {
                ContentUnavailableView(
                    listType == "collection" ? "No Releases" : "Wantlist Empty",
                    systemImage: listType == "collection" ? "music.note.house" : "heart",
                    description: Text("Use Collection > Sync Collection to import your Discogs \(listType).")
                )
            } else if filteredReleases.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                switch viewMode {
                case .list:
                    listView
                case .grid:
                    gridView
                }
            }
        }
        .navigationTitle(listType == "collection" ? "My Collection" : "Wantlist")
        .navigationSubtitle("\(filteredReleases.count) releases")
        // Split into separate toolbar content so a narrow window sheds the
        // secondary controls first: search is the primary action and stays put,
        // sort is the first thing to move into the overflow menu.
        .toolbar {
            ToolbarItemGroup {
                TextField("Search artist or title...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .help("Filter by artist or title name")

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear search")
                }
            }
            .visibilityPriority(.high)

            ToolbarItem {
                sortMenu
            }
            .visibilityPriority(.low)

            ToolbarItem {
                Picker("View Mode", selection: $viewModeRaw) {
                    Image(systemName: "list.bullet").tag(ViewMode.list.rawValue)
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Switch between list and grid view")
            }
        }
        .onChange(of: sortOrderRaw) {
            // Seed before re-sorting, so the positions come from the order the
            // user was actually looking at.
            if sortOrder.allowsReordering { seedCustomOrderIfNeeded() }
            releases.nsSortDescriptors = sortOrder.descriptors
        }
        .confirmationDialog("Remove Release", item: $releaseToDelete) { release in
            Button("Remove", role: .destructive) { delete(release) }
            Button("Cancel", role: .cancel) {}
        } message: { release in
            Text("Remove \"\(release.title ?? "this release")\" from your \(listType == "collection" ? "collection" : "wantlist")? This also removes it from your Discogs account.")
        }
        .alert("Couldn’t Complete Action", item: $actionError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - List View

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // `.reorderable()` has no enablement parameter, so it's applied
                // conditionally rather than switched off.
                if canReorder {
                    listRows.reorderable()
                } else {
                    listRows
                }
            }
            // `discogsId` is the reorder identifier because it's a stable value
            // type. NSManagedObjectID is a class cluster and fails SwiftUI's
            // identifier check; its URL representation trapped on macOS 27 betas.
            .reorderContainer(for: Release.self, itemID: \.discogsId) { difference in
                applyReorder(difference)
            }
        }
        // swipeActions has no effect outside a List without this.
        .swipeActionsContainer()
    }

    private var listRows: some DynamicViewContent {
        ForEach(filteredReleases, id: \.discogsId) { release in
            Button {
                selectedRelease = release.objectID
            } label: {
                ReleaseRow(release: release)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedRelease == release.objectID ? Color.accentColor.opacity(0.15) : Color.clear)
            }
            .buttonStyle(.plain)
            .contextMenu { releaseContextMenu(for: release) }
            // Routes through the same confirmation as the context menu
            // and the Remove command — one code path per action.
            .swipeActions {
                Button(role: .destructive) {
                    releaseToDelete = release
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
            Divider().padding(.leading, 64)
        }
    }

    // MARK: - Grid View

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220))], spacing: 16) {
                if canReorder {
                    gridCards.reorderable()
                } else {
                    gridCards
                }
            }
            .padding()
            .reorderContainer(for: Release.self, itemID: \.discogsId) { difference in
                applyReorder(difference)
            }
        }
    }

    private var gridCards: some DynamicViewContent {
        ForEach(filteredReleases, id: \.discogsId) { release in
            Button {
                selectedRelease = release.objectID
            } label: {
                ReleaseCard(release: release)
            }
            .buttonStyle(.plain)
            .contextMenu { releaseContextMenu(for: release) }
        }
    }

    // MARK: - Reordering

    /// Dragging is offered only in Custom order, which is the only order with
    /// somewhere to store the result, and only with no search filter applied —
    /// dropping a row into a filtered subset has no well-defined position in
    /// the full list.
    private var canReorder: Bool {
        sortOrder.allowsReordering && searchText.isEmpty
    }

    /// Applies a drag to the stored order and renumbers the list.
    private func applyReorder(_ difference: ReorderDifference<Int64, some Any>) {
        let moving = Set(difference.sources)
        guard !moving.isEmpty else { return }

        var ordered = Array(releases)

        // Resolve the destination BEFORE removing the dragged rows. A drag that
        // doesn't cross a row boundary reports `.before` the dragged row itself,
        // which is unfindable once removed — falling through to "append" and
        // flinging the row to the bottom of the collection.
        let destination: Int
        switch difference.destination.position {
        case .before(let id):
            destination = ordered.firstIndex { $0.discogsId == id } ?? ordered.endIndex
        case .end:
            destination = ordered.endIndex
        }

        // Removing the dragged rows shifts the insertion point left by however
        // many of them sat ahead of it.
        let removedBefore = ordered[..<destination].filter { moving.contains($0.discogsId) }.count

        var moved: [Release] = []
        ordered.removeAll { release in
            guard moving.contains(release.discogsId) else { return false }
            moved.append(release)
            return true
        }
        ordered.insert(contentsOf: moved, at: destination - removedBefore)

        renumber(ordered)
    }

    /// Gives every release an explicit position the first time the user switches
    /// to Custom order, seeded from the order they were already looking at.
    private func seedCustomOrderIfNeeded() {
        let ordered = Array(releases)
        guard ordered.allSatisfy({ $0.sortIndex == 0 }) else { return }
        renumber(ordered)
    }

    /// Writes dense positions so the order stays stable and comparable.
    private func renumber(_ ordered: [Release]) {
        for (index, release) in ordered.enumerated() {
            release.sortIndex = Int64(index)
        }
        do {
            try viewContext.save()
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func releaseContextMenu(for release: Release) -> some View {
        Button {
            let id = release.discogsId
            if let url = URL(string: "https://www.discogs.com/release/\(id)") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("Open in Discogs", systemImage: "safari")
        }

        if release.enriched {
            Divider()
        } else {
            Button {
                let objectID = release.objectID
                Task {
                    do {
                        let syncService = SyncService()
                        try await syncService.enrichSingleRelease(objectID)
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
            } label: {
                Label("Enrich", systemImage: "sparkles")
            }

            Divider()
        }

        Button(role: .destructive) {
            releaseToDelete = release
        } label: {
            Label("Remove from \(listType == "collection" ? "Collection" : "Wantlist")", systemImage: "trash")
        }
    }

    private func delete(_ release: Release) {
        // Capture identity before deletion so we can remove it from Spotlight.
        let discogsId = release.discogsId
        let releaseListType = release.listType ?? "collection"
        let objectID = release.objectID

        Task {
            do {
                let syncService = SyncService()
                try await syncService.removeRelease(objectID)
                await appModel.deindexRelease(discogsId: discogsId, listType: releaseListType)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Button {
                    sortOrderRaw = order.rawValue
                } label: {
                    if sortOrder == order {
                        Label(order.label, systemImage: "checkmark")
                    } else {
                        Text(order.label)
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Change sort order")
    }
}

// MARK: - Sort Order

enum SortOrder: String, CaseIterable {
    case dateAdded, year, artist, title, rating, custom

    var label: String {
        switch self {
        case .dateAdded: "Date Added"
        case .year: "Year"
        case .artist: "Artist"
        case .title: "Title"
        case .rating: "Rating"
        case .custom: "Custom Order"
        }
    }

    /// Whether rows can be dragged into a new position. Only the custom order
    /// has somewhere to store the result — dragging while sorted by year would
    /// just snap back.
    var allowsReordering: Bool { self == .custom }

    var descriptors: [NSSortDescriptor] {
        switch self {
        case .dateAdded: [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)]
        case .year: [NSSortDescriptor(keyPath: \Release.year, ascending: false)]
        case .artist: [NSSortDescriptor(keyPath: \Release.artist, ascending: true)]
        case .title: [NSSortDescriptor(keyPath: \Release.title, ascending: true)]
        case .rating: [NSSortDescriptor(keyPath: \Release.rating, ascending: false)]
        // Ties break on date added so newly synced records land predictably
        // before they've been given an explicit position.
        case .custom: [
            NSSortDescriptor(keyPath: \Release.sortIndex, ascending: true),
            NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)
        ]
        }
    }
}

// MARK: - View Mode

enum ViewMode: String {
    case list, grid
}
