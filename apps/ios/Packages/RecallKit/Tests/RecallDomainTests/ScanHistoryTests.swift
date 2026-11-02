import Foundation
import Testing
@testable import RecallDomain

@Suite("Earlier scans fold under a room's newest")
struct ScanHistoryTests {
    private func scan(_ id: String, _ room: String, day: Double, _ state: UploadState = .processed) -> Scan {
        Scan(id: id, room: room, createdAt: Date(timeIntervalSince1970: day * 86_400), grade: .good, directions: 12,
             frames: 60, state: state)
    }

    @Test func aRescanHoldsTheRoomAndTheFirstScanIsItsHistory() {
        let rooms = ScanHistory.byRoom([scan("a", "Living room", day: 1), scan("b", "Living room", day: 3)])
        #expect(rooms.map(\.latest.id) == ["b"])
        #expect(rooms[0].earlier.map(\.id) == ["a"])
        #expect(rooms[0].successor(of: rooms[0].earlier[0])?.id == "b")
        #expect(rooms[0].successor(of: rooms[0].latest) == nil)
    }

    @Test func eachRoomHasItsOwnCardNewestFirst() {
        let rooms = ScanHistory.byRoom([
            scan("k", "Kitchen", day: 2), scan("l1", "Living room", day: 1), scan("l2", "Living room", day: 3),
        ])
        #expect(rooms.map(\.latest.id) == ["l2", "k"])
        #expect(rooms[1].earlier.isEmpty)
    }

    @Test func aScanStillUploadingKeepsItsOwnCardAboveTheRoomsMemory() {
        let rooms = ScanHistory.byRoom([
            scan("a", "Living room", day: 1), scan("b", "Living room", day: 2),
            scan("c", "Living room", day: 3, .uploading(fraction: 0.4)),
        ])
        #expect(rooms.map(\.latest.id) == ["c", "b"])
        #expect(rooms[1].earlier.map(\.id) == ["a"])
    }

    @Test func aFailedOrLocalScanNeverFolds() {
        let rooms = ScanHistory.byRoom([
            scan("a", "Kitchen", day: 1, .failed(reason: "network")), scan("b", "Kitchen", day: 2),
            scan("c", "Kitchen", day: 0, .notUploaded),
        ])
        #expect(rooms.map(\.latest.id) == ["b", "a", "c"])
    }

    @Test func roomNamesMatchWhateverTheirCaseAndSpaces() {
        let rooms = ScanHistory.byRoom([scan("a", "living room ", day: 1), scan("b", "Living room", day: 2)])
        #expect(rooms.count == 1)
        #expect(rooms[0].earlier.map(\.id) == ["a"])
    }
}
