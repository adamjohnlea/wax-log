import Testing
@testable import Vinyl_Crate

/// Covers the grounding pass that filters the on-device model's output.
///
/// The model call itself isn't exercised here — it needs Apple Intelligence and
/// isn't deterministic. `groundedInRequest` is a pure function, and it's what
/// stops the model's habit of volunteering fields from silently narrowing a
/// search to nothing, so it's the part worth pinning down.
struct NaturalLanguageSearchTests {
    /// Builds a query with only the named fields set.
    private func query(
        artist: String = "",
        title: String = "",
        genre: String = "",
        style: String = "",
        label: String = "",
        country: String = "",
        format: String = "",
        yearFrom: Int = 0,
        yearTo: Int = 0,
        ratingMin: Int = 0
    ) -> RecordSearchQuery {
        RecordSearchQuery(
            artist: artist,
            title: title,
            genre: genre,
            style: style,
            label: label,
            country: country,
            format: format,
            yearFrom: yearFrom,
            yearTo: yearTo,
            ratingMin: ratingMin
        )
    }

    private func ground(_ q: RecordSearchQuery, _ description: String) -> RecordSearchQuery {
        NaturalLanguageSearchService.groundedInRequest(q, description: description)
    }

    @Test func keepsValuesTheRequestActuallyNamed() {
        let result = ground(query(artist: "Miles Davis"), "anything by Miles Davis")
        #expect(result.artist == "Miles Davis")
    }

    @Test func dropsValuesTheRequestNeverMentioned() {
        // The model recognises the album and volunteers its artist and label.
        let result = ground(
            query(artist: "Miles Davis", title: "Kind of Blue", label: "Columbia"),
            "Kind of Blue"
        )
        #expect(result.title == "Kind of Blue")
        #expect(result.artist.isEmpty)
        #expect(result.label.isEmpty)
    }

    /// A multi-word value must match on every word, or a phrase survives on one
    /// incidental overlap — "Blue Note" riding along on a request for "Blue".
    @Test func phraseNeedsAllOfItsWordsPresent() {
        let result = ground(query(label: "Blue Note"), "Kind of Blue")
        #expect(result.label.isEmpty)

        let kept = ground(query(label: "Blue Note"), "Blue Note pressings")
        #expect(kept.label == "Blue Note")
    }

    /// Discogs compounds genres with slashes, so matching either side is enough.
    @Test func slashSeparatedAlternativesMatchEitherSide() {
        let result = ground(query(genre: "Funk / Soul"), "my favourite soul singles")
        #expect(result.genre == "Funk / Soul")
    }

    @Test func treatsWordStemsAsTheSameWord() {
        let result = ground(query(country: "Germany"), "German pressings of Kraftwerk")
        #expect(result.country == "Germany")
    }

    @Test func clearsYearsWhenNoDateWasMentioned() {
        let result = ground(query(artist: "Kraftwerk", yearFrom: 1974, yearTo: 1978), "anything by Kraftwerk")
        #expect(result.yearFrom == 0)
        #expect(result.yearTo == 0)
    }

    @Test func keepsYearsWhenRequestHasDigitsOrEraWords() {
        let digits = ground(query(yearFrom: 1970, yearTo: 1974), "early 70s vinyl")
        #expect(digits.yearFrom == 1970)
        #expect(digits.yearTo == 1974)

        let spelled = ground(query(yearFrom: 1960, yearTo: 1969), "jazz from the sixties")
        #expect(spelled.yearFrom == 1960)
    }

    @Test func clearsRatingWhenRequestSaysNothingAboutRatings() {
        let result = ground(query(genre: "Jazz", ratingMin: 4), "jazz records")
        #expect(result.ratingMin == 0)
    }

    @Test func keepsRatingWhenRequestPraisesOrRates() {
        #expect(ground(query(ratingMin: 4), "my favourite soul records").ratingMin == 4)
        #expect(ground(query(ratingMin: 5), "five star albums").ratingMin == 5)
        #expect(ground(query(ratingMin: 4), "records I rated highly").ratingMin == 4)
    }

    /// Era talk arriving as a musical style duplicates the year range.
    @Test func rejectsEraTalkInTextFields() {
        let result = ground(query(genre: "Jazz", style: "Late 70s", yearFrom: 1975, yearTo: 1979), "late 70s jazz")
        #expect(result.style.isEmpty)
        #expect(result.genre == "Jazz")
        #expect(result.yearFrom == 1975)
    }

    /// Format is the one field where a bare number is the real value, so the
    /// era filter must not strip it.
    @Test func keepsNumericFormats() {
        #expect(ground(query(format: "7\""), "my favourite soul 7 inches").format == "7\"")
        #expect(ground(query(format: "12 inch"), "Verve 12 inch").format == "12 inch")
    }

    @Test func clearsLabelThatOnlyRestatesCountryAndGenre() {
        let result = ground(
            query(genre: "Jazz", label: "Japanese Jazz Pressings", country: "Japan", yearFrom: 1975, yearTo: 1979),
            "Japanese jazz pressings from the late 70s"
        )
        #expect(result.label.isEmpty)
        #expect(result.genre == "Jazz")
        #expect(result.country == "Japan")
    }

    /// When a name lands in both fields the model couldn't tell which it was;
    /// it committed to "label", so the duplicate artist goes.
    @Test func dropsArtistThatDuplicatesLabel() {
        let result = ground(query(artist: "Motown", label: "Motown"), "Motown singles")
        #expect(result.label == "Motown")
        #expect(result.artist.isEmpty)
    }

    @Test func dropsValuesMadeOnlyOfGenericNouns() {
        let result = ground(query(title: "singles", label: "Motown"), "Motown singles")
        #expect(result.title.isEmpty)
        #expect(result.label == "Motown")
    }
}
