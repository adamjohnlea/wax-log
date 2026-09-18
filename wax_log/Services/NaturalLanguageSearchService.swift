import Foundation
import FoundationModels

/// The structured form of a record search, as produced by the on-device model.
///
/// Mirrors the fields of `AdvancedSearchView` so a translated query can be
/// loaded straight into that form. Unset fields use empty strings and zeros
/// rather than optionals, which keeps the generation schema simple and gives
/// the model an unambiguous "not specified" value for every field.
@Generable
struct RecordSearchQuery: Equatable {
    @Guide(description: "Performing artist or band name. Empty string if the request doesn't name one.")
    var artist: String

    @Guide(description: "Album or release title. Empty string if the request doesn't name one.")
    var title: String

    @Guide(description: "Broad musical genre, such as Jazz, Rock, Funk / Soul, Electronic. Empty string if not mentioned.")
    var genre: String

    @Guide(description: "Specific musical style, such as Bebop, Hard Rock, Shoegaze, Deep House. Empty string if not mentioned.")
    var style: String

    @Guide(description: "Record label, such as Blue Note or Motown. Empty string if not mentioned.")
    var label: String

    @Guide(description: "Country of release, such as UK, US, Japan. Empty string if not mentioned.")
    var country: String

    @Guide(description: "Physical format, such as Vinyl, LP, 7\", CD. Empty string if not mentioned.")
    var format: String

    @Guide(description: "Earliest release year, or 0 when the request sets no lower bound.")
    var yearFrom: Int

    @Guide(description: "Latest release year, or 0 when the request sets no upper bound.")
    var yearTo: Int

    @Guide(description: "Minimum star rating the person wants, from 1 to 5. Use 0 when the request says nothing about ratings.", .range(0...5))
    var ratingMin: Int
}

/// Translates a plain-language description of a record search into
/// `RecordSearchQuery` using Apple's on-device system language model.
///
/// The translation only populates the Advanced Search form — the user sees the
/// resulting query and can edit it before running the search, so a poor
/// translation is visible and correctable rather than silently changing which
/// records match.
enum NaturalLanguageSearchService {
    /// A user-facing explanation of why natural-language search can't run, or
    /// `nil` when the on-device model is ready.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turn on Apple Intelligence in System Settings to describe searches in plain language."
        case .unavailable(.deviceNotEligible):
            "This Mac doesn't support Apple Intelligence."
        case .unavailable(.modelNotReady):
            "The on-device model is still downloading. Try again in a few minutes."
        case .unavailable:
            "Plain-language search isn't available right now."
        }
    }

    private static let instructions = """
    You turn a person's description of the records they want to find into \
    structured search fields for their personal vinyl record collection.

    Fill in a field only when the request clearly implies it. Leave text fields \
    as an empty string and numeric fields as 0 when the request says nothing \
    about them. Never invent an artist, label, genre, or country that the \
    request didn't mention.

    Read decades as year ranges: "the 60s" means 1960 through 1969, "early 70s" \
    means 1970 through 1974, "late 80s" means 1985 through 1989. A single year \
    sets both bounds to that year.

    Read praise as a rating floor: "highly rated", "my favourites", or "records \
    I love" means a minimum rating of 4. "Five star" means 5.
    """

    /// Translates `description` into structured search fields.
    ///
    /// - Parameter description: A plain-language search, e.g.
    ///   "jazz records from the 60s I rated highly".
    /// - Returns: The structured query the model produced.
    /// - Throws: A `LanguageModelError` if the model is unavailable or the
    ///   request can't be satisfied.
    static func query(from description: String) async throws -> RecordSearchQuery {
        // A fresh session per translation: each search is independent, so there's
        // no transcript worth carrying over between them.
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: description, generating: RecordSearchQuery.self)
        return response.content
    }
}
