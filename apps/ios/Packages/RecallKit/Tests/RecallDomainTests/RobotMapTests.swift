import Foundation
import Testing
@testable import RecallDomain

@Suite("Robot map")
struct RobotMapTests {
    /// 3 x 2 cells: top row free, occupied, unknown; bottom row all free.
    let pgm = Data("P5\n3 2\n255\n".utf8) + Data([254, 0, 128, 254, 254, 254])

    @Test func readsAPGMAsRecallWritesIt() throws {
        let m = try #require(RobotMap(pgm: pgm, resolution: 0.1, origin: (-1, -2)))
        #expect(m.width == 3 && m.height == 2 && m.shades.count == 6)
        #expect(m.cell(row: 0, column: 0) == .free && m.cell(row: 0, column: 1) == .occupied && m.cell(row: 0, column: 2) == .unknown)
        #expect(RobotMap(pgm: Data("P2\n3 2\n255\n".utf8), resolution: 0.1, origin: (0, 0)) == nil)  // only binary P5
        #expect(RobotMap(pgm: Data("P5\n3 2\n255\n".utf8) + Data([1, 2]), resolution: 0.1, origin: (0, 0)) == nil)  // short
    }

    @Test func shadesReadAsNav2ReadsThem() {
        #expect(RobotMap.cell(254) == .free && RobotMap.cell(0) == .occupied && RobotMap.cell(128) == .unknown)
    }

    @Test func roomPointsLandOnTheImageWithItsTopRowAtTheHighestY() throws {
        let m = try #require(RobotMap(pgm: pgm, resolution: 0.1, origin: (-1, -2)))
        let p = m.pixel(x: -0.95, y: -1.95)  // the lower-left cell's middle
        #expect(abs(p.column - 0.5) < 1e-9 && abs(p.row - 1.5) < 1e-9)  // bottom row of the image
    }

    @Test func aPackageNamesItsZipByRoom() {
        let map = RobotMap(width: 1, height: 1, resolution: 0.1, origin: (0, 0), shades: [254])
        #expect(RobotMapPackage(room: "Living room", map: map, things: [], files: [:]).name == "Recall-Living-room-robot-map")
    }
}
