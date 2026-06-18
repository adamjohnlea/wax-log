import SwiftUI

struct DiscogsSearchView: View {
    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var currentPage = 1
    @State private var totalPages = 0
    @State private var actionMessage: ActionMessage?

    var body: some View {
        VStack(spacing: 0) {
            // Results
            if !results.isEmpty {
                List {
                    ForEach(results, id: \.id) { result in
                        DiscogsSearchResultRow(result: result) { listType in
                            addToList(result: result, listType: listType)
                        }
                    }

                    // Pagination
                    if currentPage < totalPages {
                        HStack {
                            Spacer()
                            Button("Load More") {
                                loadMore()
                            }
                            .disabled(isSearching)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            } else if isSearching {
                Spacer()
                ProgressView("Searching Discogs...")
                Spacer()
            } else if hasSearched {
                ContentUnavailableView.search(text: searchText)
            } else {
                ContentUnavailableView(
                    "Search Discogs",
                    systemImage: "magnifyingglass",
                    description: Text("Search the Discogs database to find and add releases.")
                )
            }
        }
        .searchable(text: $searchText, prompt: "Search Discogs database...")
        .onSubmit(of: .search) {
            performSearch()
        }
        .navigationTitle("Discogs Search")
        .overlay(alignment: .bottom) {
            if let message = actionMessage {
                HStack {
                    Label(message.text, systemImage: message.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(message.isSuccess ? .green : .red)
                }
                .padding()
                .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { actionMessage = nil }
                    }
                }
            }
        }
    }

    // MARK: - Search

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        hasSearched = true
        currentPage = 1
        results = []

        Task {
            do {
                let response = try await DiscogsClient.shared.search(query: searchText, page: 1)
                results = response.results
                totalPages = response.pagination.pages
            } catch {
                actionMessage = ActionMessage(text: error.localizedDescription, isSuccess: false)
            }
            isSearching = false
        }
    }

    private func loadMore() {
        guard currentPage < totalPages else { return }
        isSearching = true
        let nextPage = currentPage + 1

        Task {
            do {
                let response = try await DiscogsClient.shared.search(query: searchText, page: nextPage)
                results.append(contentsOf: response.results)
                currentPage = nextPage
            } catch {
                actionMessage = ActionMessage(text: error.localizedDescription, isSuccess: false)
            }
            isSearching = false
        }
    }

    // MARK: - Add to List

    private func addToList(result: SearchResult, listType: String) {
        Task {
            do {
                try await appModel.syncService.addSearchResultToList(result, listType: listType)
                let label = listType == "collection" ? "collection" : "wantlist"
                withAnimation {
                    actionMessage = ActionMessage(text: "Added to \(label)!", isSuccess: true)
                }
            } catch {
                withAnimation {
                    actionMessage = ActionMessage(text: error.localizedDescription, isSuccess: false)
                }
            }
        }
    }

    private struct ActionMessage {
        let text: String
        let isSuccess: Bool
    }
}

// MARK: - Search Result Row

struct DiscogsSearchResultRow: View {
    let result: SearchResult
    let onAdd: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            AsyncImage(url: URL(string: result.thumb ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let year = result.year, !year.isEmpty {
                        Text(year)
                    }
                    if let format = result.format?.first {
                        Text(format)
                    }
                    if let label = result.label?.first {
                        Text(label)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let genre = result.genre?.joined(separator: ", "), !genre.isEmpty {
                    Text(genre)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Add buttons
            Menu {
                Button {
                    onAdd("collection")
                } label: {
                    Label("Add to Collection", systemImage: "music.note.house")
                }

                Button {
                    onAdd("wantlist")
                } label: {
                    Label("Add to Wantlist", systemImage: "heart")
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 2)
    }
}
