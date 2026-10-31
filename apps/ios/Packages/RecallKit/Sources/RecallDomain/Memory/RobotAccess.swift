import Foundation

/// Whether robots may read this home's memory (off by default; the owner turns it on), and where they reach it.
public struct RobotAccessStatus: Sendable, Equatable {
    public let on: Bool
    public let a2aURL: String
    public let agentCardURL: String
    public let exportURL: String

    public init(on: Bool, a2aURL: String, agentCardURL: String, exportURL: String) {
        self.on = on; self.a2aURL = a2aURL; self.agentCardURL = agentCardURL; self.exportURL = exportURL
    }
}

/// One room's memory for a robot (the Mac's robot export): the Nav2 map files and where things are. Geometry and
/// labels only.
public struct RobotMapPackage: Sendable, Equatable {
    public struct Thing: Sendable, Equatable {
        public let label: String
        public let color: String?
        public let x: Double, y: Double

        public init(label: String, color: String?, x: Double, y: Double) {
            self.label = label; self.color = color; self.x = x; self.y = y
        }

        public var title: String { [color, label].compactMap { $0 }.joined(separator: " ") }
    }

    public let room: String
    public let map: RobotMap
    public let things: [Thing]
    /// The files a ROS 2 robot loads, by name: map.pgm, map.yaml, objects.json, room.json.
    public let files: [String: Data]

    public init(room: String, map: RobotMap, things: [Thing], files: [String: Data]) {
        self.room = room; self.map = map; self.things = things; self.files = files
    }

    /// "Recall-Living-room-robot-map".
    public var name: String {
        "Recall-" + room.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-") + "-robot-map"
    }
}

/// The map a robot navigates by: Nav2's trinary PGM (254 free, 0 occupied, 128 unknown), its origin and resolution.
public struct RobotMap: Sendable, Equatable {
    public enum Cell: Sendable, Equatable { case free, occupied, unknown }

    public let width: Int
    public let height: Int
    public let resolution: Double
    public let origin: (x: Double, y: Double)
    /// Image rows, top first (the map's highest y is the top row), as stored in the PGM.
    public let shades: [UInt8]

    public static func == (a: RobotMap, b: RobotMap) -> Bool {
        a.width == b.width && a.height == b.height && a.shades == b.shades && a.resolution == b.resolution
    }

    public init(width: Int, height: Int, resolution: Double, origin: (x: Double, y: Double), shades: [UInt8]) {
        self.width = width; self.height = height; self.resolution = resolution; self.origin = origin; self.shades = shades
    }

    /// Reads a binary (P5) PGM as Recall writes it ("P5\n<w> <h>\n255\n" then the pixels).
    public init?(pgm data: Data, resolution: Double, origin: (x: Double, y: Double)) {
        var fields: [String] = []
        var i = data.startIndex
        while fields.count < 4, i < data.endIndex {
            while i < data.endIndex, Character(UnicodeScalar(data[i])).isWhitespace { i = data.index(after: i) }
            var token = ""
            while i < data.endIndex, !Character(UnicodeScalar(data[i])).isWhitespace {
                token.append(Character(UnicodeScalar(data[i]))); i = data.index(after: i)
            }
            fields.append(token)
        }
        guard fields.count == 4, fields[0] == "P5", let w = Int(fields[1]), let h = Int(fields[2]), i < data.endIndex
        else { return nil }
        let start = data.index(after: i)  // one whitespace byte after maxval
        guard data.distance(from: start, to: data.endIndex) >= w * h else { return nil }
        self.init(width: w, height: h, resolution: resolution, origin: origin,
                  shades: Array(data[start..<data.index(start, offsetBy: w * h)]))
    }

    /// Nav2's reading of a shade (trinary, negate 0, thresholds 0.65 / 0.25).
    public static func cell(_ shade: UInt8) -> Cell {
        let occ = (255 - Double(shade)) / 255
        return occ > 0.65 ? .occupied : occ < 0.25 ? .free : .unknown
    }

    public func cell(row: Int, column: Int) -> Cell { Self.cell(shades[row * width + column]) }

    /// Where a point of the room (map frame, metres) falls in the image: (column, row from the top), fractional.
    public func pixel(x: Double, y: Double) -> (column: Double, row: Double) {
        ((x - origin.x) / resolution, Double(height) - (y - origin.y) / resolution)
    }
}
