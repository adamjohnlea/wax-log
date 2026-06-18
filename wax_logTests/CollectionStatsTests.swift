import Testing
import CoreData
@testable import Vinyl_Crate

@MainActor
struct CollectionStatsTests {
    @Test func emptyCollection() {
        let stats = CollectionStats(releases: [])
        #expect(stats.total == 0)
        #expect(stats.artists == 0)
        #expect(stats.genres == 0)
        #expect(stats.averageRating == nil)
        #expect(stats.averageRatingText == "N/A")
        #expect(stats.spokenSummary.contains("empty"))
    }

    @Test func countsUniqueArtistsAndGenres() {
        let context = TestStore.makeContext()
        let releases = [
            TestStore.makeRelease(in: context, artist: "A", genre: "Rock, Pop", rating: 4),
            TestStore.makeRelease(in: context, artist: "A", genre: "Jazz", rating: 2),
            TestStore.makeRelease(in: context, artist: "B", genre: "Rock", rating: 0)
        ]

        let stats = CollectionStats(releases: releases)
        #expect(stats.total == 3)
        #expect(stats.artists == 2)          // A, B (deduplicated)
        #expect(stats.genres == 3)           // Rock, Pop, Jazz (split + deduplicated)
        #expect(stats.averageRating == 3.0)  // (4 + 2) / 2, unrated excluded
        #expect(stats.averageRatingText == "3.0")
    }

    @Test func singularWordingForOneRecord() {
        let context = TestStore.makeContext()
        let stats = CollectionStats(releases: [TestStore.makeRelease(in: context, artist: "A", genre: "Rock")])
        #expect(stats.spokenSummary.contains("1 record "))   // "record", not "records"
    }
}
