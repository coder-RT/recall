import Foundation
import Testing
@testable import RecallDomain

@Suite("Why Recall thinks so")
struct EvidenceTests {
    let at = Date(timeIntervalSince1970: 1_793_330_461)  // 2026-10-30 03:21:01 UTC

    @Test func aSightingIsOneSentenceYouCanHear() {
        let s = Sighting(observationId: "ob1", label: "keys", room: "Living room", seenAt: at, confidence: 0.92,
                         current: true, segmenter: "sam-3.1", reconstructor: "map-anything-apache@00f9c24")
        let warsaw = TimeZone(identifier: "Europe/Warsaw")!
        #expect(s.spoken(timeZone: warsaw).hasPrefix("Seen in the Living room scan on "))
        #expect(s.spoken(timeZone: warsaw).hasSuffix(", 92% sure. Found by SAM 3.1; placed by MapAnything."))
    }

    @Test func anOlderSightingSaysALaterScanMovedIt() {
        let s = Sighting(observationId: "ob0", label: "keys", room: "Office", seenAt: at, confidence: 0.8, current: false,
                         reconstructor: "arkit-depth")
        #expect(s.spoken().contains("A later scan saw it somewhere else."))
        #expect(s.spoken().hasSuffix("Placed by the iPhone's LiDAR depth."))
    }

    @Test func theSummaryNamesTheModelAndTheTime() {
        let e = Evidence(question: "q", text: "t", model: "meta-models/muse-spark-open-1026", latencyMs: 2300,
                         tools: ["find_object"], sightings: [])
        #expect(e.summary == "Phrased by Muse Spark Open from 0 sightings, in 2.3 seconds.")
    }
}
