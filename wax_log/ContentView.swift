import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedSection: SidebarSection? = .collection
    @State private var syncService = SyncService()

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSection)
        } content: {
            Group {
                switch selectedSection {
                case .collection:
                    CollectionView(listType: "collection")
                case .wantlist:
                    CollectionView(listType: "wantlist")
                case .statistics:
                    StatisticsView()
                case .randomizer:
                    RandomizerView()
                case .discogsSearch:
                    DiscogsSearchView()
                case .tools:
                    ToolsView()
                case .smartCollection(let objectID):
                    if let sc = try? viewContext.existingObject(with: objectID) as? SmartCollection {
                        SmartCollectionView(smartCollection: sc)
                    }
                case nil:
                    ContentUnavailableView("Vinyl Crate", systemImage: "music.note.house", description: Text("Select a section from the sidebar."))
                }
            }
            .navigationDestination(for: NSManagedObjectID.self) { objectID in
                if let release = try? viewContext.existingObject(with: objectID) as? Release {
                    ReleaseDetailView(release: release)
                }
            }
        } detail: {
            ContentUnavailableView("Select a Release", systemImage: "opticaldisc", description: Text("Choose a release to view its details."))
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncCollection)) { _ in
            Task { await syncService.performInitialSync() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshCollection)) { _ in
            Task { await syncService.performIncrementalRefresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .enrichAll)) { _ in
            Task { await syncService.enrichAllReleases() }
        }
    }
}

// MARK: - Sidebar

enum SidebarSection: Hashable {
    case collection
    case wantlist
    case statistics
    case randomizer
    case discogsSearch
    case tools
    case smartCollection(NSManagedObjectID)
}

struct SidebarView: View {
    @Binding var selection: SidebarSection?
    @State private var showingAddSmartCollection = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)],
        predicate: NSPredicate(format: "listType == %@", "collection")
    )
    private var collectionReleases: FetchedResults<Release>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)],
        predicate: NSPredicate(format: "listType == %@", "wantlist")
    )
    private var wantlistReleases: FetchedResults<Release>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SmartCollection.createdAt, ascending: true)]
    )
    private var smartCollections: FetchedResults<SmartCollection>

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("My Collection", systemImage: "music.note.house")
                    .badge(collectionReleases.count)
                    .tag(SidebarSection.collection)

                Label("Wantlist", systemImage: "heart")
                    .badge(wantlistReleases.count)
                    .tag(SidebarSection.wantlist)
            }

            if !smartCollections.isEmpty {
                Section("Smart Collections") {
                    ForEach(smartCollections, id: \.objectID) { sc in
                        SmartCollectionRow(smartCollection: sc)
                            .tag(SidebarSection.smartCollection(sc.objectID))
                    }
                }
            }

            Section("Discover") {
                Label("Statistics", systemImage: "chart.bar")
                    .tag(SidebarSection.statistics)

                Label("Randomizer", systemImage: "dice")
                    .tag(SidebarSection.randomizer)

                Label("Discogs Search", systemImage: "magnifyingglass")
                    .tag(SidebarSection.discogsSearch)
            }

            Section {
                Label("Tools", systemImage: "wrench")
                    .tag(SidebarSection.tools)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .navigationTitle("Vinyl Crate")
        .toolbar {
            ToolbarItem {
                Button {
                    showingAddSmartCollection = true
                } label: {
                    Label("New Smart Collection", systemImage: "plus")
                }
                .help("Create a new Smart Collection")
            }
        }
        .sheet(isPresented: $showingAddSmartCollection) {
            AddSmartCollectionView()
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
