import Foundation
import Testing
@testable import RecallDomain

@Suite("Privacy note")
struct PrivacyTests {
    @Test func robotLineSaysWhatRobotsGet() {
        let off = PrivacyStatus(storedOn: "This Mac", sent: [], robotAccess: false, auditDays: 90)
        #expect(off.robotLine == "Robot Access is off: robots get nothing.")
        let on = PrivacyStatus(storedOn: "This Mac", sent: [], robotAccess: true, auditDays: 90)
        #expect(on.robotLine.contains("never photos"))
    }

    @Test func theNoteNamesWhatLeavesAndWhatNeverDoes() {
        #expect(PrivacyNote.short.contains("own Mac") && PrivacyNote.short.contains("Meta's models online"))
        #expect(PrivacyNote.never.contains { $0.contains("No Recall server") })
        #expect(PrivacyNote.controls.map(\.title) == ["Delete a scan", "Forget a thing", "Robot Access", "Private mode"])
    }
}
