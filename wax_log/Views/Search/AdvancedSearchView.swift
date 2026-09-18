import SwiftUI

struct AdvancedSearchView: View {
    @Binding var searchText: String
    @Environment(\.dismiss) private var dismiss

    @State private var artist = ""
    @State private var title = ""
    @State private var genre = ""
    @State private var style = ""
    @State private var label = ""
    @State private var country = ""
    @State private var format = ""
    @State private var yearFrom = ""
    @State private var yearTo = ""
    @State private var ratingMin = 0
    @State private var barcode = ""

    @State private var plainLanguage = ""
    @State private var isTranslating = false
    @State private var translationError: String?

    /// Read once per presentation: Apple Intelligence availability doesn't
    /// change while a sheet is open.
    private let unavailableReason = NaturalLanguageSearchService.unavailableReason

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Describe It") {
                    HStack {
                        TextField("jazz records from the 60s I rated highly", text: $plainLanguage)
                            .onSubmit(translate)

                        Button(action: translate) {
                            if isTranslating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Fill In")
                            }
                        }
                        .disabled(!canTranslate)
                        .help("Turn this description into search fields using the on-device model")
                    }
                    .disabled(unavailableReason != nil)

                    if let unavailableReason {
                        Text(unavailableReason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Text Fields") {
                    TextField("Artist", text: $artist)
                    TextField("Title", text: $title)
                    TextField("Label", text: $label)
                    TextField("Genre", text: $genre)
                    TextField("Style", text: $style)
                    TextField("Country", text: $country)
                    TextField("Format", text: $format)
                    TextField("Barcode", text: $barcode)
                }

                Section("Year") {
                    HStack {
                        TextField("From", text: $yearFrom)
                            .frame(width: 80)
                        Text("to")
                            .foregroundStyle(.secondary)
                        TextField("To", text: $yearTo)
                            .frame(width: 80)
                    }
                }

                Section("Rating") {
                    HStack(spacing: 4) {
                        ForEach(0...5, id: \.self) { star in
                            if star == 0 {
                                Button("Any") {
                                    ratingMin = 0
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(ratingMin == 0 ? .primary : .secondary)
                                .padding(.trailing, 8)
                            } else {
                                Button {
                                    ratingMin = ratingMin == star ? 0 : star
                                } label: {
                                    Image(systemName: star <= ratingMin ? "star.fill" : "star")
                                        .foregroundStyle(star <= ratingMin ? .yellow : .secondary)
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Minimum rating \(star) star\(star == 1 ? "" : "s")")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Clear All") {
                    clearFields()
                }

                Spacer()

                Text(buildQuery())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Search") {
                    searchText = buildQuery()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(buildQuery().isEmpty)
            }
            .padding()
        }
        .frame(width: 480, height: 600)
        .onAppear {
            parseExistingQuery()
        }
        .alert("Couldn’t Read That Search", item: $translationError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Plain-Language Translation

    private var canTranslate: Bool {
        unavailableReason == nil
            && !isTranslating
            && !plainLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Asks the on-device model to turn `plainLanguage` into search fields.
    /// The result populates the form rather than searching directly, so the
    /// user reviews the query before it runs.
    private func translate() {
        guard canTranslate else { return }
        let description = plainLanguage.trimmingCharacters(in: .whitespacesAndNewlines)

        isTranslating = true
        Task {
            do {
                apply(try await NaturalLanguageSearchService.query(from: description))
            } catch {
                translationError = error.localizedDescription
            }
            isTranslating = false
        }
    }

    /// Loads a translated query into the form. `barcode` is left alone — the
    /// model doesn't produce one, so clearing it would discard user input.
    private func apply(_ query: RecordSearchQuery) {
        artist = query.artist
        title = query.title
        genre = query.genre
        style = query.style
        label = query.label
        country = query.country
        format = query.format
        yearFrom = query.yearFrom > 0 ? String(query.yearFrom) : ""
        yearTo = query.yearTo > 0 ? String(query.yearTo) : ""
        ratingMin = query.ratingMin
    }

    // MARK: - Query Builder

    private func buildQuery() -> String {
        var parts: [String] = []

        if !artist.isEmpty { parts.append("artist:\(quoteIfNeeded(artist))") }
        if !title.isEmpty { parts.append("title:\(quoteIfNeeded(title))") }
        if !label.isEmpty { parts.append("label:\(quoteIfNeeded(label))") }
        if !genre.isEmpty { parts.append("genre:\(quoteIfNeeded(genre))") }
        if !style.isEmpty { parts.append("style:\(quoteIfNeeded(style))") }
        if !country.isEmpty { parts.append("country:\(quoteIfNeeded(country))") }
        if !format.isEmpty { parts.append("format:\(quoteIfNeeded(format))") }
        if !barcode.isEmpty { parts.append("barcode:\(barcode)") }

        if !yearFrom.isEmpty && !yearTo.isEmpty {
            parts.append("year:\(yearFrom)..\(yearTo)")
        } else if !yearFrom.isEmpty {
            parts.append("year:\(yearFrom)")
        }

        if ratingMin > 0 {
            parts.append("rating:\(ratingMin)..5")
        }

        return parts.joined(separator: " ")
    }

    private func quoteIfNeeded(_ value: String) -> String {
        value.contains(" ") ? "\"\(value)\"" : value
    }

    // MARK: - Parse Existing

    private func parseExistingQuery() {
        guard !searchText.isEmpty else { return }

        // Simple parse: extract known prefixes
        let terms = searchText.split(separator: " ").map(String.init)
        for term in terms {
            guard let colonIdx = term.firstIndex(of: ":") else { continue }
            let field = String(term[..<colonIdx]).lowercased()
            let value = String(term[term.index(after: colonIdx)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            switch field {
            case "artist": artist = value
            case "title": self.title = value
            case "label": label = value
            case "genre": genre = value
            case "style": style = value
            case "country": country = value
            case "format": format = value
            case "barcode": barcode = value
            case "year":
                if value.contains("..") {
                    let parts = value.split(separator: ".").filter { !$0.isEmpty }
                    if parts.count == 2 {
                        yearFrom = String(parts[0])
                        yearTo = String(parts[1])
                    }
                } else {
                    yearFrom = value
                }
            case "rating":
                if value.contains("..") {
                    let parts = value.split(separator: ".").filter { !$0.isEmpty }
                    if let first = parts.first, let min = Int(first) { ratingMin = min }
                } else if let val = Int(value) {
                    ratingMin = val
                }
            default: break
            }
        }
    }

    private func clearFields() {
        artist = ""
        title = ""
        genre = ""
        style = ""
        label = ""
        country = ""
        format = ""
        yearFrom = ""
        yearTo = ""
        ratingMin = 0
        barcode = ""
        plainLanguage = ""
    }
}
