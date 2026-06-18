import Testing
import CoreData
@testable import Vinyl_Crate

@MainActor
struct SearchServiceTests {
    @Test func artistPrefixMatchesArtistOnly() {
        let context = TestStore.makeContext()
        let floyd = TestStore.makeRelease(in: context, title: "Animals", artist: "Pink Floyd")
        let beatles = TestStore.makeRelease(in: context, title: "Revolver", artist: "The Beatles")

        let predicate = SearchService.predicate(from: "artist:Floyd")
        #expect(predicate.evaluate(with: floyd))
        #expect(!predicate.evaluate(with: beatles))
    }

    @Test func quotedPhraseIsOneTerm() {
        let context = TestStore.makeContext()
        let floyd = TestStore.makeRelease(in: context, artist: "Pink Floyd")

        let predicate = SearchService.predicate(from: "artist:\"Pink Floyd\"")
        #expect(predicate.evaluate(with: floyd))
    }

    @Test func yearExactMatch() {
        let context = TestStore.makeContext()
        let r77 = TestStore.makeRelease(in: context, year: 1977)
        let r85 = TestStore.makeRelease(in: context, year: 1985)

        let predicate = SearchService.predicate(from: "year:1977")
        #expect(predicate.evaluate(with: r77))
        #expect(!predicate.evaluate(with: r85))
    }

    @Test func yearRangeMatch() {
        let context = TestStore.makeContext()
        let inRange = TestStore.makeRelease(in: context, year: 1975)
        let outOfRange = TestStore.makeRelease(in: context, year: 1985)

        let predicate = SearchService.predicate(from: "year:1970..1979")
        #expect(predicate.evaluate(with: inRange))
        #expect(!predicate.evaluate(with: outOfRange))
    }

    @Test func ratingRangeMatch() {
        let context = TestStore.makeContext()
        let high = TestStore.makeRelease(in: context, rating: 5)
        let low = TestStore.makeRelease(in: context, rating: 2)

        let predicate = SearchService.predicate(from: "rating:4..5")
        #expect(predicate.evaluate(with: high))
        #expect(!predicate.evaluate(with: low))
    }

    @Test func bareTermSearchesAcrossFields() {
        let context = TestStore.makeContext()
        let jazz = TestStore.makeRelease(in: context, artist: "Miles Davis", genre: "Jazz")
        let rock = TestStore.makeRelease(in: context, artist: "Nirvana", genre: "Rock")

        let predicate = SearchService.predicate(from: "Jazz")
        #expect(predicate.evaluate(with: jazz))
        #expect(!predicate.evaluate(with: rock))
    }

    @Test func multipleTermsAreAnded() {
        let context = TestStore.makeContext()
        let match = TestStore.makeRelease(in: context, artist: "Miles Davis", year: 1959)
        let wrongYear = TestStore.makeRelease(in: context, artist: "Miles Davis", year: 1970)

        let predicate = SearchService.predicate(from: "artist:Davis year:1959")
        #expect(predicate.evaluate(with: match))
        #expect(!predicate.evaluate(with: wrongYear))
    }

    @Test func listTypeFilterRestrictsByList() {
        let context = TestStore.makeContext()
        let collectionItem = TestStore.makeRelease(in: context, listType: "collection")
        let wantlistItem = TestStore.makeRelease(in: context, listType: "wantlist")

        let predicate = SearchService.predicate(from: "", listType: "collection")
        #expect(predicate.evaluate(with: collectionItem))
        #expect(!predicate.evaluate(with: wantlistItem))
    }

    @Test func emptyQueryMatchesEverythingWhenNoList() {
        let context = TestStore.makeContext()
        let any = TestStore.makeRelease(in: context)

        let predicate = SearchService.predicate(from: "")
        #expect(predicate.evaluate(with: any))
    }
}
