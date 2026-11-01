import Foundation
import Testing
@testable import RecallDomain

@Suite("What Recall trusts, in words")
struct TrustTests {
    private func thing(photos: Int?, trusted: Bool, confidence: Double = 0.55) -> Thing {
        Thing(id: "w", label: "wallet", color: "green", heightM: 0.4, heightBand: "knee", confidence: confidence,
              needsReview: !trusted, photos: photos, trusted: trusted, seenAt: Date(timeIntervalSince1970: 0))
    }

    @Test func theEvidenceSaysHowManyPhotosAndHowSure() {
        #expect(thing(photos: 1, trusted: false).evidence == "Seen in 1 photo, 55 percent sure")
        #expect(thing(photos: 19, trusted: true, confidence: 0.63).evidence == "Seen in 19 photos, 63 percent sure")
        #expect(thing(photos: nil, trusted: true).evidence == "55 percent sure")  // kept before photos were counted
    }

    @Test func aThingSeenOnceSaysSoInsteadOfCheck() {
        #expect(thing(photos: 1, trusted: false).checkMark == "Seen once")
        #expect(thing(photos: 2, trusted: false).checkMark == "Check")  // Careful wants 3
        #expect(thing(photos: 4, trusted: true).checkMark == "Check")  // trusted but unsure
    }

    @Test func everyLevelExplainsItself() {
        #expect(TrustLevel.allCases.map(\.title) == ["Careful", "Balanced", "Everything"])
        #expect(TrustLevel.allCases.allSatisfy { !$0.explanation.isEmpty })
    }
}
