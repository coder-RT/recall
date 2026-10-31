import Foundation
import Testing
@testable import RecallDomain

private func thing(_ label: String, name: String? = nil) -> Thing {
    Thing(id: label, label: label, name: name, heightM: 0.8, heightBand: "waist", confidence: 0.9,
          seenAt: Date(timeIntervalSince1970: 0))
}

@Suite("Said at once")
struct AcknowledgementTests {
    let known = [thing("keys"), thing("glasses", name: "reading glasses"), thing("bag"), thing("laptop")]

    @Test func namesWhatThePersonAskedFor() {
        #expect(Acknowledgement.line(for: "Where are my keys?", known: known) == "Looking for your keys.")
        #expect(Acknowledgement.line(for: "where's my key", known: known) == "Looking for your keys.")
        #expect(Acknowledgement.line(for: "Where did I put my reading glasses?", known: known)
                == "Looking for your reading glasses.")
        #expect(Acknowledgement.line(for: "Have you seen my BAG", known: known) == "Looking for your bag.")
    }

    @Test func otherwiseJustSaysItIsChecking() {
        #expect(Acknowledgement.line(for: "Where is my umbrella?", known: known) == "Checking.")
        #expect(Acknowledgement.line(for: "Where is the keyboard?", known: known) == "Checking.")  // not "keys"
        #expect(Acknowledgement.line(for: "", known: []) == "Checking.")
    }
}
