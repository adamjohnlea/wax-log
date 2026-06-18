import Testing
import CoreData
@testable import Vinyl_Crate

@MainActor
struct ReleaseDisplayTests {
    @Test func displayArtistStripsDisambiguation() {
        let context = TestStore.makeContext()
        let single = TestStore.makeRelease(in: context, artist: "Jack White (2)")
        #expect(single.displayArtist == "Jack White")

        let multi = TestStore.makeRelease(in: context, artist: "Artist A (2), Artist B (3)")
        #expect(multi.displayArtist == "Artist A, Artist B")
    }

    @Test func displayArtistHandlesEmpty() {
        let context = TestStore.makeContext()
        let release = TestStore.makeRelease(in: context, artist: "")
        #expect(release.displayArtist == "Unknown Artist")
    }

    @Test func displayYear() {
        let context = TestStore.makeContext()
        #expect(TestStore.makeRelease(in: context, year: 0).displayYear == "Unknown")
        #expect(TestStore.makeRelease(in: context, year: 1977).displayYear == "1977")
    }

    @Test func accessibilityRating() {
        let context = TestStore.makeContext()
        #expect(TestStore.makeRelease(in: context, rating: 0).accessibilityRating == "Not rated")
        #expect(TestStore.makeRelease(in: context, rating: 3).accessibilityRating == "Rated 3 out of 5")
    }
}
