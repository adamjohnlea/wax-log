import SwiftUI
import CoreData

struct CollectionView: View {
    let listType: String
    @Environment(\.managedObjectContext) private var viewContext
    @State private var sortOrder: SortOrder = .dateAdded
    @State private var viewMode: ViewMode = .list
    @State private var searchText = ""
    @State private var showingAdvancedSearch = false

    @FetchRequest private var releases: FetchedResults<Release>

    init(listType: String) {
        self.listType = listType
        _releases = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)],
            predicate: NSPredicate(format: "listType == %@", listType),
            animation: .default
        )
    }

    var body: some View {
        Group {
            if releases.isEmpty && searchText.isEmpty {
                ContentUnavailableView(
                    listType == "collection" ? "No Releases" : "Wantlist Empty",
                    systemImage: listType == "collection" ? "music.note.house" : "heart",
                    description: Text("Use Tools > Sync to import your Discogs \(listType).")
                )
            } else if releases.isEmpty && !searchText.isEmpty {
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
        .searchable(text: $searchText, prompt: "Search \(listType)... (use artist:, genre:, year: for advanced)")
        .navigationTitle(listType == "collection" ? "My Collection" : "Wantlist")
        .navigationSubtitle("\(releases.count) releases")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingAdvancedSearch = true
                } label: {
                    Label("Advanced Search", systemImage: "line.3.horizontal.decrease.circle")
                }

                sortMenu

                Picker("View", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                }
                .pickerStyle(.segmented)
            }
        }
        .onChange(of: sortOrder) {
            releases.nsSortDescriptors = sortOrder.descriptors
        }
        .onChange(of: searchText) {
            applySearch()
        }
        .sheet(isPresented: $showingAdvancedSearch) {
            AdvancedSearchView(searchText: $searchText)
        }
    }

    // MARK: - Search

    private func applySearch() {
        if searchText.isEmpty {
            releases.nsPredicate = NSPredicate(format: "listType == %@", listType)
        } else {
            releases.nsPredicate = SearchService.predicate(from: searchText, listType: listType)
        }
    }

    // MARK: - List View

    private var listView: some View {
        List(releases, id: \.objectID) { release in
            NavigationLink(value: release.objectID) {
                ReleaseRow(release: release)
            }
        }
    }

    // MARK: - Grid View

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220))], spacing: 16) {
                ForEach(releases, id: \.objectID) { release in
                    NavigationLink(value: release.objectID) {
                        ReleaseCard(release: release)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
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
