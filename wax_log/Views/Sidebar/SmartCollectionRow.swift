import SwiftUI
import CoreData

struct SmartCollectionRow: View {
    @ObservedObject var smartCollection: SmartCollection
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var matchCount = 0

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
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("Are you sure you want to delete \"\(smartCollection.name ?? "")\"? This cannot be undone.")
            }
            .alert(
                "Delete Failed",
                isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
            // Recompute the badge when the query changes or any context save occurs,
            // rather than running a count fetch on every render.
            .task(id: smartCollection.query) { recomputeCount() }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
                recomputeCount()
            }
    }

    private func delete() {
        viewContext.delete(smartCollection)
        do {
            try viewContext.save()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func recomputeCount() {
        let predicate = SearchService.predicate(from: smartCollection.query ?? "")
        let request = NSFetchRequest<Release>(entityName: "Release")
        request.predicate = predicate
        matchCount = (try? viewContext.count(for: request)) ?? 0
    }
}
