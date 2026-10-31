import Foundation
import Testing
@testable import RecallDomain

@Suite("What deleting a scan reaches")
struct DeleteReachTests {
    private func scan(_ state: UploadState) -> Scan {
        Scan(id: "s", room: "Kitchen", createdAt: Date(timeIntervalSince1970: 0), grade: .good, directions: 10,
             frames: 50, state: state)
    }

    @Test func onlyThePhoneUntilUploaded() {
        #expect(scan(.notUploaded).deleteReach == .phoneOnly)
    }

    @Test func waitsWhileTheMacIsBusyWithIt() {
        for state in [UploadState.preparing, .uploading(fraction: 0.4), .finishing, .processing] {
            #expect(scan(state).deleteReach == .waitForMac)
        }
    }

    @Test func bothOnceTheMacHasIt() {
        #expect(scan(.processed).deleteReach == .phoneAndMac)
        #expect(scan(.failed(reason: "network")).deleteReach == .phoneAndMac)
    }
}
