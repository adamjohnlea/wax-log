import Foundation
import CoreData

enum SearchService {
    /// Parses a query string and returns an NSPredicate.
    ///
    /// Supports:
    /// - Plain text: searches across artist, title, label, genre, style, notes, tracklist
    /// - Field prefixes: `artist:`, `title:`, `genre:`, `style:`, `label:`, `country:`, `format:`, `barcode:`, `notes:`
    /// - Year exact: `year:1977`
    /// - Year range: `year:1977..1982`
    /// - Rating: `rating:4` or `rating:3..5`
    /// - Multiple terms combined with AND
    static func predicate(from query: String, listType: String? = nil) -> NSPredicate {
        var predicates: [NSPredicate] = []

        if let listType {
            predicates.append(NSPredicate(format: "listType == %@", listType))
        }

        let terms = parseTerms(query)

        for term in terms {
            if let fieldPredicate = parseFieldPrefix(term) {
                predicates.append(fieldPredicate)
            } else {
                // Full-text search across multiple fields
                predicates.append(fullTextPredicate(for: term))
            }
        }

        guard !predicates.isEmpty else {
            return NSPredicate(value: true)
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    // MARK: - Term Parsing

    /// Splits query into terms, respecting quoted strings.
    /// e.g. `artist:"Pink Floyd" year:1977` -> ["artist:\"Pink Floyd\"", "year:1977"]
    private static func parseTerms(_ query: String) -> [String] {
        var terms: [String] = []
        var current = ""
        var inQuotes = false

        for char in query {
            if char == "\"" {
                inQuotes.toggle()
                current.append(char)
            } else if char == " " && !inQuotes {
                if !current.isEmpty {
                    terms.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            terms.append(current)
        }

        return terms
    }

    // MARK: - Field Prefix Parsing

    private static func parseFieldPrefix(_ term: String) -> NSPredicate? {
        guard let colonIndex = term.firstIndex(of: ":") else { return nil }

        let field = String(term[term.startIndex..<colonIndex]).lowercased()
        var value = String(term[term.index(after: colonIndex)...])

        // Strip quotes
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        guard !value.isEmpty else { return nil }

        switch field {
        case "artist":
            return NSPredicate(format: "artist CONTAINS[cd] %@", value)
        case "title":
            return NSPredicate(format: "title CONTAINS[cd] %@", value)
        case "genre":
            return NSPredicate(format: "genre CONTAINS[cd] %@", value)
        case "style":
            return NSPredicate(format: "style CONTAINS[cd] %@", value)
        case "label":
            return NSPredicate(format: "label CONTAINS[cd] %@", value)
        case "country":
            return NSPredicate(format: "country CONTAINS[cd] %@", value)
        case "format":
            return NSPredicate(format: "format CONTAINS[cd] %@", value)
        case "barcode":
            return NSPredicate(format: "barcode CONTAINS[cd] %@", value)
        case "notes":
            return NSPredicate(format: "personalNotes CONTAINS[cd] %@ OR notes CONTAINS[cd] %@", value, value)
        case "year":
            return yearPredicate(value)
        case "rating":
            return ratingPredicate(value)
        default:
            return nil
        }
    }

    // MARK: - Year Predicate

    private static func yearPredicate(_ value: String) -> NSPredicate? {
        // Range: year:1977..1982
        if value.contains("..") {
            let parts = value.split(separator: ".").filter { !$0.isEmpty }
            guard parts.count == 2,
                  let start = Int32(parts[0]),
                  let end = Int32(parts[1]) else {
                return nil
            }
            return NSPredicate(format: "year >= %d AND year <= %d", start, end)
        }

        // Exact: year:1977
        guard let year = Int32(value) else { return nil }
        return NSPredicate(format: "year == %d", year)
    }

    // MARK: - Rating Predicate

    private static func ratingPredicate(_ value: String) -> NSPredicate? {
        // Range: rating:3..5
        if value.contains("..") {
            let parts = value.split(separator: ".").filter { !$0.isEmpty }
            guard parts.count == 2,
                  let start = Int16(parts[0]),
                  let end = Int16(parts[1]) else {
                return nil
            }
            return NSPredicate(format: "rating >= %d AND rating <= %d", start, end)
        }

        // Exact: rating:4
        guard let rating = Int16(value) else { return nil }
        return NSPredicate(format: "rating == %d", rating)
    }

    // MARK: - Full Text

    private static func fullTextPredicate(for term: String) -> NSPredicate {
        let fields = ["artist", "title", "label", "genre", "style", "notes", "personalNotes", "tracklist"]
        let subpredicates = fields.map { field in
            NSPredicate(format: "%K CONTAINS[cd] %@", field, term)
        }
        return NSCompoundPredicate(orPredicateWithSubpredicates: subpredicates)
    }
}
