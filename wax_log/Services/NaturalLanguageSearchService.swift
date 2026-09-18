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
/// `nonisolated` because none of this is UI state: the model call and the
/// grounding pass are both pure with respect to the app's actors, which also
/// lets the grounding logic be unit-tested directly.
nonisolated enum NaturalLanguageSearchService {
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

    // Kept deliberately free of concrete artist/label/album names: worked
    // examples containing real values made the model copy those values into
    // unrelated answers (a Kraftwerk query came back labelled "Blue Note").
    // Over-filling is instead held down by the declarative rules here plus the
    // grounding pass in `groundedInRequest`.
    private static let instructions = """
    You turn a person's description of the records they want to find into \
    structured search fields for their personal vinyl record collection.

    Every field has a "not specified" value: an empty string for text fields, 0 \
    for numeric fields. Start with every field not specified and fill one in \
    only when the request states that information directly.

    Copy values out of the request. Do not add anything from your own knowledge \
    of music: if you recognise a record or an artist that the request names, do \
    not fill in the other fields you happen to know about it. Every field you \
    add that the person didn't ask for narrows their search, and narrows it to \
    nothing if you get it wrong.

    Never infer one field from another:
    - Do not derive a genre or style from an artist, label, or album name.
    - Do not derive years from when an artist was active or a record came out.
    - Do not fill in format or country unless the request names one.
    - Do not set ratingMin unless the request explicitly mentions ratings or \
    praises the records.

    The label field is the record company that issued the record. Only put a \
    name there when the request is clearly naming a record company; a country, \
    a genre, or a format is never a label. Put a place name in the country \
    field only.

    Work out year ranges arithmetically. A bare decade spans all ten of its \
    years: the 60s is 1960 to 1969, the 70s is 1970 to 1979. "Early" is the \
    first five years of that decade: early 70s is 1970 to 1974. "Late" is the \
    last five: late 70s is 1975 to 1979. "Mid" is the middle: mid 70s is 1974 \
    to 1976. A single year sets both bounds to that year.

    Read explicit praise as a rating floor: general praise means ratingMin 4, \
    and superlatives mean 5.
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
        return groundedInRequest(response.content, description: description)
    }

    // MARK: - Grounding

    /// Words too common to count as evidence that a value came from the request.
    /// Includes the generic nouns people use for records themselves — a label of
    /// "Japanese Jazz Pressings" is only country and genre plus one such noun.
    private static let ignoredWords: Set<String> = [
        "a", "an", "and", "any", "anything", "by", "for", "from", "in", "i",
        "it", "me", "my", "of", "on", "or", "the", "with",
        "album", "albums", "copies", "copy", "disc", "discs", "issue", "issues",
        "lp", "lps", "pressing", "pressings", "record", "records", "release",
        "releases", "single", "singles", "stuff", "thing", "things"
    ]

    /// Words that signal the person actually cares about release dates.
    private static let eraWords: Set<String> = [
        "fifties", "sixties", "seventies", "eighties", "nineties", "decade",
        "year", "years", "old", "older", "recent", "vintage", "era"
    ]

    /// Word stems that signal the person actually cares about ratings.
    private static let ratingStems = [
        "rate", "rated", "rating", "star", "favourite", "favorite", "love",
        "best", "highly", "top", "great"
    ]

    /// Removes field values the request never actually mentioned.
    ///
    /// The model reliably volunteers extra fields — a label it associates with
    /// an album, a country it remembers for a pressing, a rating nobody asked
    /// for — and each unrequested field narrows the search, to nothing when the
    /// guess is wrong. A text value survives when at least one of its
    /// meaningful words appears in what the person typed, which keeps genuine
    /// normalisations (asking for "soul" and getting the "Funk / Soul" genre)
    /// while dropping invented ones.
    /// Exposed rather than private so it can be exercised directly in tests:
    /// it's a pure function, unlike the model call that feeds it.
    static func groundedInRequest(
        _ query: RecordSearchQuery,
        description: String
    ) -> RecordSearchQuery {
        var grounded = query
        let requested = words(in: description)

        // `rejectEraNoise` is off for format, where bare numbers are the real
        // values ("7", "12 inch") rather than a smuggled-in year range.
        func grounding(_ value: String, rejectEraNoise: Bool = true) -> String {
            guard !rejectEraNoise || !isEraNoise(value) else { return "" }

            // Discogs compounds alternatives with slashes ("Funk / Soul"), so any
            // one side matching is enough. Within a single alternative every word
            // must match, or a phrase survives on one incidental word — "Blue
            // Note" would otherwise be kept by a request for "Kind of Blue".
            let alternatives = value
                .components(separatedBy: "/")
                .map { words(in: $0).filter { !ignoredWords.contains($0) } }
                .filter { !$0.isEmpty }

            // Every word was generic filler ("singles", "albums"), so the value
            // identifies nothing and would only narrow the search.
            guard !alternatives.isEmpty else { return "" }

            let matches = alternatives.contains { alternative in
                alternative.allSatisfy { candidate in
                    requested.contains { $0 == candidate || isPrefixMatch($0, candidate) }
                }
            }
            return matches ? value : ""
        }

        grounded.artist = grounding(query.artist)
        grounded.title = grounding(query.title)
        grounded.genre = grounding(query.genre)
        grounded.style = grounding(query.style)
        grounded.label = grounding(query.label)
        grounded.country = grounding(query.country)
        grounded.format = grounding(query.format, rejectEraNoise: false)

        // The model tends to echo a country or genre into `label` as well
        // ("Japanese jazz" arriving as label "Japanese Jazz"). A label that only
        // restates another field isn't a label.
        if restates(grounded.label, anyOf: [grounded.country, grounded.genre, grounded.style, grounded.format]) {
            grounded.label = ""
        }

        // When the same name lands in both artist and label the model couldn't
        // tell which it was; it already committed to "label", so keep that and
        // drop the duplicate rather than requiring both to match one record.
        if !grounded.label.isEmpty, restates(grounded.artist, anyOf: [grounded.label]) {
            grounded.artist = ""
        }

        // Years need a digit ("60s", "1985") or an era word to be justified.
        let mentionsEra = description.contains(where: \.isNumber)
            || requested.contains { eraWords.contains($0) }
        if !mentionsEra {
            grounded.yearFrom = 0
            grounded.yearTo = 0
        }

        // A rating floor needs the person to have raised ratings at all.
        let mentionsRating = requested.contains { word in
            ratingStems.contains { word.hasPrefix($0) }
        }
        if !mentionsRating {
            grounded.ratingMin = 0
        }

        return grounded
    }

    /// Modifiers that narrow a decade rather than describe music.
    private static let eraModifiers: Set<String> = ["early", "mid", "late", "s"]

    /// Whether `value` is made up entirely of era talk — "Late 70s" arriving as
    /// a musical style, for instance. Such a value describes the year range,
    /// which is already captured in `yearFrom`/`yearTo`.
    private static func isEraNoise(_ value: String) -> Bool {
        let candidates = words(in: value).filter { !ignoredWords.contains($0) }
        guard !candidates.isEmpty else { return false }
        return candidates.allSatisfy { word in
            isYearLike(word) || eraWords.contains(word) || eraModifiers.contains(word)
        }
    }

    /// Whether a word is a year or decade token: "1985", "70", "70s".
    private static func isYearLike(_ word: String) -> Bool {
        word.contains(where: \.isNumber)
            && word.allSatisfy { $0.isNumber || $0 == "s" }
    }

    /// Whether every meaningful word of `value` also appears in one of `others`,
    /// meaning `value` carries no information those fields don't already hold.
    private static func restates(_ value: String, anyOf others: [String]) -> Bool {
        let candidates = words(in: value).filter { !ignoredWords.contains($0) }
        guard !candidates.isEmpty else { return false }
        let elsewhere = others.flatMap { words(in: $0) }
        guard !elsewhere.isEmpty else { return false }
        return candidates.allSatisfy { candidate in
            elsewhere.contains { $0 == candidate || isPrefixMatch($0, candidate) }
        }
    }

    /// Lowercased, punctuation-free words, so "Funk / Soul" yields "funk", "soul".
    private static func words(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Treats "german" and "germany" as the same word, without matching on
    /// fragments so short they'd collide by accident.
    private static func isPrefixMatch(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs.count >= 4, rhs.count >= 4 else { return false }
        return lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)
    }
}
