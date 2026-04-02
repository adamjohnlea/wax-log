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

    var body: some View {
        VStack(spacing: 0) {
            Form {
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
                                Image(systemName: star <= ratingMin ? "star.fill" : "star")
                                    .foregroundStyle(star <= ratingMin ? .yellow : .secondary)
                                    .font(.title3)
                                    .onTapGesture {
                                        ratingMin = ratingMin == star ? 0 : star
                                    }
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
        .frame(width: 480, height: 520)
        .onAppear {
            parseExistingQuery()
        }
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
                    if let min = Int(parts[0]) { ratingMin = min }
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
    }
}
