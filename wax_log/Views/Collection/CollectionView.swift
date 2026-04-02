import SwiftUI
import CoreData

struct CollectionView: View {
    let listType: String
    @Environment(\.managedObjectContext) private var viewContext
    @State private var sortOrder: SortOrder = .dateAdded
    @State private var viewMode: ViewMode = .list
    @State private var searchText = ""

    @FetchRequest private var releases: FetchedResults<Release>

    init(listType: String) {
        self.listType = listType
        _releases = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)],
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

                Picker("View Mode", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Switch between list and grid view")
            }
        }
        .onChange(of: sortOrder) {
            releases.nsSortDescriptors = sortOrder.descriptors
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToListView)) { _ in
            viewMode = .list
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToGridView)) { _ in
            viewMode = .grid
        }
    }

    // MARK: - List View

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredReleases, id: \.objectID) { release in
                    NavigationLink(value: release.objectID) {
                        ReleaseRow(release: release)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
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
                    NavigationLink(value: release.objectID) {
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
                    let syncService = SyncService()
                    await syncService.enrichSingleRelease(objectID)
                }
            } label: {
                Label("Enrich", systemImage: "sparkles")
            }

            Divider()
        }

        Button(role: .destructive) {
            viewContext.delete(release)
            try? viewContext.save()
        } label: {
            Label("Remove from \(listType == "collection" ? "Collection" : "Wantlist")", systemImage: "trash")
        }
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Button {
                    sortOrder = order
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

enum SortOrder: CaseIterable {
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

enum ViewMode {
    case list, grid
}
