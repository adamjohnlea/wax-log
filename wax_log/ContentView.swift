import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        NavigationSplitView {
            // Route sidebar taps through selectSection so a user switching
            // sections clears the detail selection, while programmatic
            // navigation (openRelease/surpriseMe) can set both at once.
            SidebarView(selection: Binding(
                get: { appModel.selectedSection },
                set: { appModel.selectSection($0) }
            ))
        } content: {
            Group {
                switch appModel.selectedSection {
                case .collection:
                    CollectionView(listType: "collection", selectedRelease: $appModel.selectedRelease)
                case .wantlist:
                    CollectionView(listType: "wantlist", selectedRelease: $appModel.selectedRelease)
                case .statistics:
                    StatisticsView()
                case .randomizer:
                    RandomizerView(selectedRelease: $appModel.selectedRelease)
                case .discogsSearch:
                    DiscogsSearchView()
                case .tools:
                    ToolsView()
                case .smartCollection(let objectID):
                    if let sc = try? viewContext.existingObject(with: objectID) as? SmartCollection {
                        SmartCollectionView(smartCollection: sc, selectedRelease: $appModel.selectedRelease)
                    }
                case nil:
                    ContentUnavailableView("Vinyl Crate", systemImage: "music.note.house", description: Text("Select a section from the sidebar."))
                }
            }
        } detail: {
            if let selectedRelease = appModel.selectedRelease,
               let release = try? viewContext.existingObject(with: selectedRelease) as? Release {
                ReleaseDetailView(release: release)
                    .id(selectedRelease)
            } else {
                ContentUnavailableView("Select a Release", systemImage: "opticaldisc", description: Text("Choose a release to view its details."))
            }
        }
        .onAppear {
            appModel.restoreSavedSection()
            Task { await appModel.indexCollectionIfNeeded() }
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

    var rawValue: String {
        switch self {
        case .collection: "collection"
        case .wantlist: "wantlist"
        case .statistics: "statistics"
        case .randomizer: "randomizer"
        case .discogsSearch: "discogsSearch"
        case .tools: "tools"
        case .smartCollection: "collection"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "collection": self = .collection
        case "wantlist": self = .wantlist
        case "statistics": self = .statistics
        case "randomizer": self = .randomizer
        case "discogsSearch": self = .discogsSearch
        case "tools": self = .tools
        // Smart collections aren't restorable from a raw string (their identity is an
        // NSManagedObjectID), so unknown values fail and the default selection is kept.
        default: return nil
        }
    }
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
        .environment(AppModel(persistenceController: .preview))
}
