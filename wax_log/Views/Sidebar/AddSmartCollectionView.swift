import SwiftUI

struct AddSmartCollectionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var query = ""
    @State private var showingAdvancedSearch = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name)

                LabeledContent("Query") {
                    HStack {
                        TextField("e.g. genre:Jazz year:1960..1969", text: $query)

                        Button {
                            showingAdvancedSearch = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || query.isEmpty)
            }
            .padding()
        }
        .frame(width: 440, height: 200)
        .sheet(isPresented: $showingAdvancedSearch) {
            AdvancedSearchView(searchText: $query)
        }
    }

    private func save() {
        let collection = SmartCollection(context: viewContext)
        collection.name = name
        collection.query = query
        collection.createdAt = Date()
        try? viewContext.save()
        dismiss()
    }
}
