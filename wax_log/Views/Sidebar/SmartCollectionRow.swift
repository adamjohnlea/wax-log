import SwiftUI
import CoreData

struct SmartCollectionRow: View {
    @ObservedObject var smartCollection: SmartCollection
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        Label(smartCollection.name ?? "Untitled", systemImage: "magnifyingglass")
            .badge(matchCount)
            .contextMenu {
                Button("Delete", role: .destructive) {
                    viewContext.delete(smartCollection)
                    try? viewContext.save()
                }
            }
    }

    private var matchCount: Int {
        let predicate = SearchService.predicate(from: smartCollection.query ?? "")
        let request = NSFetchRequest<Release>(entityName: "Release")
        request.predicate = predicate
        return (try? viewContext.count(for: request)) ?? 0
    }
}
