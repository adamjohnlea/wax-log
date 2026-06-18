import Testing
import CoreData
@testable import Vinyl_Crate

@MainActor
struct ReleaseEntityTests {
    @Test func parseIDRoundTrips() {
        let collection = ReleaseEntity.parseID("12345-collection")
        #expect(collection?.discogsId == 12345)
        #expect(collection?.listType == "collection")

        let wantlist = ReleaseEntity.parseID("678-wantlist")
        #expect(wantlist?.discogsId == 678)
        #expect(wantlist?.listType == "wantlist")
    }

    @Test func parseIDRejectsMalformed() {
        #expect(ReleaseEntity.parseID("nodash") == nil)
        #expect(ReleaseEntity.parseID("abc-collection") == nil)
        #expect(ReleaseEntity.parseID("") == nil)
    }

    @Test func entityMapsReleaseFields() {
        let context = TestStore.makeContext()
        let release = TestStore.makeRelease(
            in: context,
            discogsId: 42,
            title: "Kind of Blue",
            artist: "Miles Davis (2)",
            year: 1959,
            listType: "collection"
        )

        let entity = ReleaseEntity(release: release)
        #expect(entity.id == "42-collection")
        #expect(entity.discogsId == 42)
        #expect(entity.title == "Kind of Blue")
        #expect(entity.displayArtist == "Miles Davis")   // Discogs "(2)" suffix stripped
        #expect(entity.year == 1959)
    }

    @Test func idAndParseAreInverse() {
        let context = TestStore.makeContext()
        let release = TestStore.makeRelease(in: context, discogsId: 999, listType: "wantlist")
        let entity = ReleaseEntity(release: release)

        let parsed = ReleaseEntity.parseID(entity.id)
        #expect(parsed?.discogsId == 999)
        #expect(parsed?.listType == "wantlist")
    }
}
