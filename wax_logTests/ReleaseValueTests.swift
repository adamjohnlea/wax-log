import Testing
import CoreData
@testable import Vinyl_Crate

@MainActor
struct ReleaseValueTests {
    private static let suggestionsJSON = """
    {"Very Good Plus (VG+)": {"currency": "USD", "value": 20.0}, "Near Mint (NM or M-)": {"currency": "USD", "value": 30.0}}
    """

    @Test func valueUsesMatchingMediaCondition() {
        let context = TestStore.makeContext()
        let release = TestStore.makeRelease(in: context)
        release.priceSuggestions = Self.suggestionsJSON
        release.mediaCondition = "Near Mint (NM or M-)"

        let value = release.estimatedValue
        #expect(value?.amount == 30.0)
        #expect(value?.currency == "USD")
        guard case .condition(let condition) = value?.basis else {
            Issue.record("Expected condition basis, got \(String(describing: value?.basis))")
            return
        }
        #expect(condition == "Near Mint (NM or M-)")
    }

    @Test func ungradedReleaseAssumesVGPlus() {
        let context = TestStore.makeContext()
        let release = TestStore.makeRelease(in: context)
        release.priceSuggestions = Self.suggestionsJSON

        let value = release.estimatedValue
        #expect(value?.amount == 20.0)
        guard case .assumedVGPlus = value?.basis else {
            Issue.record("Expected assumed VG+ basis, got \(String(describing: value?.basis))")
            return
        }
    }

    @Test func unrecognizedConditionAssumesVGPlus() {
        let context = TestStore.makeContext()
        let release = TestStore.makeRelease(in: context)
        release.priceSuggestions = Self.suggestionsJSON
        release.mediaCondition = "Sealed"

        let value = release.estimatedValue
        #expect(value?.amount == 20.0)
        guard case .assumedVGPlus = value?.basis else {
            Issue.record("Expected assumed VG+ basis, got \(String(describing: value?.basis))")
            return
        }
    }

    @Test func noSalesHistoryFallsBackToLowestListing() {
        let context = TestStore.makeContext()
        let release = TestStore.makeRelease(in: context)
        release.lowestPrice = 12.5
        release.priceCurrency = "USD"

        let value = release.estimatedValue
        #expect(value?.amount == 12.5)
        #expect(value?.currency == "USD")
        guard case .lowestListing = value?.basis else {
            Issue.record("Expected lowest listing basis, got \(String(describing: value?.basis))")
            return
        }
    }

    @Test func noPriceDataReturnsNil() {
        let context = TestStore.makeContext()
        let release = TestStore.makeRelease(in: context)
        #expect(release.estimatedValue == nil)
    }

    @Test func decodesVideos() {
        let context = TestStore.makeContext()
        let release = TestStore.makeRelease(in: context)
        release.videos = #"[{"uri": "https://www.youtube.com/watch?v=abc", "title": "Full Album"}]"#

        let videos = release.decodedVideos
        #expect(videos?.count == 1)
        #expect(videos?.first?.uri == "https://www.youtube.com/watch?v=abc")
        #expect(videos?.first?.title == "Full Album")
    }
}
