import SwiftUI
import CoreData

struct SmartCollectionRow: View {
    @ObservedObject var smartCollection: SmartCollection
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Label(smartCollection.name ?? "Untitled", systemImage: "magnifyingglass")
            .badge(matchCount)
            .contextMenu {
                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
            .alert("Delete Smart Collection", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    viewContext.delete(smartCollection)
                    try? viewContext.save()
                }
            } message: {
                Text("Are you sure you want to delete \"\(smartCollection.name ?? "")\"? This cannot be undone.")
            }
    }

    private var matchCount: Int {
        let predicate = SearchService.predicate(from: smartCollection.query ?? "")
        let request = NSFetchRequest<Release>(entityName: "Release")
        request.predicate = predicate
        return (try? viewContext.count(for: request)) ?? 0
    }
}
