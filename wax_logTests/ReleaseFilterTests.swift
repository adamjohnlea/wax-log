import Testing
import CoreData
@testable import Vinyl_Crate

/// Covers the `ReleaseFilter` → `NSPredicate` mapping that backs the Shortcuts
/// "Find Records" action. Each filter is evaluated against real `Release`
/// objects so the Core Data attribute names are verified too — a typo'd key
/// would silently match nothing in production.
@MainActor
struct ReleaseFilterTests {
    @Test func textFiltersMatchOnTheRightField() {
        let context = TestStore.makeContext()
        let release = TestStore.makeRelease(
            in: context,
            title: "Kind of Blue",
            artist: "Miles Davis (2)",
            genre: "Jazz"
        )

        #expect(ReleaseFilter(key: "title", test: .containsText("of Bl")).predicate.evaluate(with: release))
        #expect(ReleaseFilter(key: "title", test: .hasPrefixText("Kind")).predicate.evaluate(with: release))
        #expect(ReleaseFilter(key: "title", test: .equalToText("kind of blue")).predicate.evaluate(with: release))
        #expect(ReleaseFilter(key: "genre", test: .equalToText("Jazz")).predicate.evaluate(with: release))

        // A title match must not be satisfied by the artist field.
        #expect(!ReleaseFilter(key: "title", test: .containsText("Miles")).predicate.evaluate(with: release))
    }

    @Test func artistFilterMatchesRawStoredName() {
        let context = TestStore.makeContext()
        let release = TestStore.makeRelease(in: context, artist: "Miles Davis (2)")

        // The stripped `displayArtist` isn't stored, so the filter runs against
        // the raw `artist` column — a substring match works regardless.
        #expect(ReleaseFilter(key: "artist", test: .containsText("Miles Davis")).predicate.evaluate(with: release))
        #expect(ReleaseFilter(key: "artist", test: .hasPrefixText("miles")).predicate.evaluate(with: release))
    }

    @Test func numericFiltersCompareOrdering() {
        let context = TestStore.makeContext()
        let release = TestStore.makeRelease(in: context, year: 1959, rating: 4)

        #expect(ReleaseFilter(key: "year", test: .equalToNumber(1959)).predicate.evaluate(with: release))
        #expect(ReleaseFilter(key: "year", test: .lessThanNumber(1970)).predicate.evaluate(with: release))
        #expect(ReleaseFilter(key: "year", test: .greaterThanNumber(1950)).predicate.evaluate(with: release))
        #expect(!ReleaseFilter(key: "year", test: .greaterThanNumber(1959)).predicate.evaluate(with: release))

        #expect(ReleaseFilter(key: "rating", test: .greaterThanNumber(3)).predicate.evaluate(with: release))
        #expect(!ReleaseFilter(key: "rating", test: .lessThanNumber(4)).predicate.evaluate(with: release))
    }

    @Test func listTypeFilterSeparatesCollectionFromWantlist() {
        let context = TestStore.makeContext()
        let owned = TestStore.makeRelease(in: context, discogsId: 1, listType: "collection")
        let wanted = TestStore.makeRelease(in: context, discogsId: 2, listType: "wantlist")

        let filter = ReleaseFilter(key: "listType", test: .equalToText("wantlist")).predicate
        #expect(filter.evaluate(with: wanted))
        #expect(!filter.evaluate(with: owned))
    }

    /// The query combines comparators with `mode`, so verify both compounds
    /// behave as the Shortcuts "all/any" toggle implies.
    @Test func comparatorsCombineByMode() {
        let context = TestStore.makeContext()
        let release = TestStore.makeRelease(in: context, year: 1959, genre: "Jazz")

        let jazz = ReleaseFilter(key: "genre", test: .equalToText("Jazz")).predicate
        let modern = ReleaseFilter(key: "year", test: .greaterThanNumber(2000)).predicate

        #expect(!NSCompoundPredicate(andPredicateWithSubpredicates: [jazz, modern]).evaluate(with: release))
        #expect(NSCompoundPredicate(orPredicateWithSubpredicates: [jazz, modern]).evaluate(with: release))
    }
}
