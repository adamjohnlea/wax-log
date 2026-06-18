import SwiftUI
import CoreData

struct SmartCollectionView: View {
    @ObservedObject var smartCollection: SmartCollection
    @Binding var selectedRelease: NSManagedObjectID?
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewMode: ViewMode = .list
    @State private var sortOrder: SortOrder = .dateAdded

    @FetchRequest private var releases: FetchedResults<Release>

    init(smartCollection: SmartCollection, selectedRelease: Binding<NSManagedObjectID?>) {
        self.smartCollection = smartCollection
        self._selectedRelease = selectedRelease
        let predicate = SearchService.predicate(from: smartCollection.query ?? "")
        _releases = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)],
            predicate: predicate,
            animation: .default
        )
    }

    var body: some View {
        Group {
            if releases.isEmpty {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "magnifyingglass",
                    description: Text("No releases match \"\(smartCollection.query ?? "")\".")
                )
            } else {
                switch viewMode {
                case .list:
                    List(releases, id: \.objectID, selection: $selectedRelease) { release in
                        ReleaseRow(release: release)
                            .tag(release.objectID)
                    }
                case .grid:
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220))], spacing: 16) {
                            ForEach(releases, id: \.objectID) { release in
                                Button {
                                    selectedRelease = release.objectID
                                } label: {
                                    ReleaseCard(release: release)
                                        .background(selectedRelease == release.objectID ? Color.accentColor.opacity(0.15) : Color.clear)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle(smartCollection.name ?? "Smart Collection")
        .navigationSubtitle("\(releases.count) releases")
        .toolbar {
            ToolbarItemGroup {
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
    }
}
