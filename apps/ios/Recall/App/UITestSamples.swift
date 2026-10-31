import Foundation
import RecallDomain

/// Made-up things for the UI tests (launch argument `-UITestSampleThings`), so Find and Found can be checked in the
/// simulator, which has no Mac paired. Only the tests pass the argument; the app never shows these otherwise.
enum UITestSamples {
    static let enabled = ProcessInfo.processInfo.arguments.contains("-UITestSampleThings")

    static let things: [Thing] = {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        func t(_ id: String, _ label: String, _ color: String?, room: String?, landmark: String?, band: String = "waist",
               relation: String = "near", sure: Bool = true) -> Thing {
            Thing(id: id, label: label, color: color, heightM: 0.8, heightBand: band, landmark: landmark,
                  relation: relation, room: room, confidence: sure ? 0.85 : 0.6, needsReview: !sure, seenAt: at)
        }
        return [
            t("s1", "keys", "beige", room: "Living room", landmark: "desk"),
            t("s2", "bag", "grey", room: "Living room", landmark: "desk", band: "knee", sure: false),
            t("s3", "book", "red", room: "Living room", landmark: "shelf", relation: "on", sure: false),
            t("s4", "bottle", "grey", room: "Living room", landmark: nil, band: "floor"),
            t("s5", "mug", "white", room: "Kitchen", landmark: "counter", relation: "on"),
            t("s6", "wallet", "brown", room: "Kitchen", landmark: "counter", relation: "on"),
        ]
    }()
}
