import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedSection: SidebarSection? = .collection

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
                case .settings:
                    SettingsView()
                case .smartCollection(let objectID):
                    if let sc = try? viewContext.existingObject(with: objectID) as? SmartCollection {
                        SmartCollectionView(smartCollection: sc)
                    }
                case nil:
                    Text("Select a section")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationDestination(for: NSManagedObjectID.self) { objectID in
                if let release = try? viewContext.existingObject(with: objectID) as? Release {
                    ReleaseDetailView(release: release)
                }
            }
        } detail: {
            Text("Select a release")
                .font(.title2)
                .foregroundStyle(.secondary)
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
    case settings
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

            Section {
                Label("Statistics", systemImage: "chart.bar")
                    .tag(SidebarSection.statistics)

                Label("Randomizer", systemImage: "dice")
                    .tag(SidebarSection.randomizer)

                Label("Discogs Search", systemImage: "magnifyingglass")
                    .tag(SidebarSection.discogsSearch)

                Label("Tools", systemImage: "wrench")
                    .tag(SidebarSection.tools)

                Label("Settings", systemImage: "gear")
                    .tag(SidebarSection.settings)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .navigationTitle("Wax Log")
        .toolbar {
            ToolbarItem {
                Button {
                    showingAddSmartCollection = true
                } label: {
                    Label("New Smart Collection", systemImage: "plus")
                }
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
