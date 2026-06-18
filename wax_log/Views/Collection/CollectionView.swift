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

                sortMenu

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
            releases.nsSortDescriptors = sortOrder.descriptors
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToListView)) { _ in
            viewModeRaw = ViewMode.list.rawValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToGridView)) { _ in
            viewModeRaw = ViewMode.grid.rawValue
        }
        .confirmationDialog(
            "Remove Release",
            isPresented: Binding(get: { releaseToDelete != nil }, set: { if !$0 { releaseToDelete = nil } }),
            presenting: releaseToDelete
        ) { release in
            Button("Remove", role: .destructive) { delete(release) }
            Button("Cancel", role: .cancel) {}
        } message: { release in
            Text("Remove \"\(release.title ?? "this release")\" from your local \(listType == "collection" ? "collection" : "wantlist")? It will reappear on the next sync unless you also remove it on Discogs.")
        }
        .alert(
            "Couldn’t Complete Action",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - List View

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredReleases, id: \.objectID) { release in
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
                    Divider().padding(.leading, 64)
                }
            }
        }
    }

    // MARK: - Grid View

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220))], spacing: 16) {
                ForEach(filteredReleases, id: \.objectID) { release in
                    Button {
                        selectedRelease = release.objectID
                    } label: {
                        ReleaseCard(release: release)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { releaseContextMenu(for: release) }
                }
            }
            .padding()
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

        viewContext.delete(release)
        do {
            try viewContext.save()
            Task { await appModel.deindexRelease(discogsId: discogsId, listType: releaseListType) }
        } catch {
            actionError = error.localizedDescription
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
    case dateAdded, year, artist, title, rating

    var label: String {
        switch self {
        case .dateAdded: "Date Added"
        case .year: "Year"
        case .artist: "Artist"
        case .title: "Title"
        case .rating: "Rating"
        }
    }

    var descriptors: [NSSortDescriptor] {
        switch self {
        case .dateAdded: [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)]
        case .year: [NSSortDescriptor(keyPath: \Release.year, ascending: false)]
        case .artist: [NSSortDescriptor(keyPath: \Release.artist, ascending: true)]
        case .title: [NSSortDescriptor(keyPath: \Release.title, ascending: true)]
        case .rating: [NSSortDescriptor(keyPath: \Release.rating, ascending: false)]
        }
    }
}

// MARK: - View Mode

enum ViewMode: String {
    case list, grid
}
