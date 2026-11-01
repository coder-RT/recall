import Foundation

/// The lists' groupings: by place (room, then the furniture it's on or near), by height, or by kind. Each group
/// knows its count and how many still need checking, for its heading.
public struct ThingGroup: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let things: [Thing]
    /// Smaller groups inside (the furniture within a room); empty for a flat group.
    public let spots: [ThingGroup]

    public init(id: String, title: String, things: [Thing], spots: [ThingGroup] = []) {
        self.id = id; self.title = title; self.things = things; self.spots = spots
    }

    public var count: Int { things.count }
    public var toCheck: Int { things.filter { $0.needsReview && !$0.confirmed }.count }

    /// "Living room, 10 things, 4 to check": the heading as one sentence.
    public var summary: String {
        let n = count == 1 ? "1 thing" : "\(count) things"
        return toCheck == 0 ? "\(title), \(n)" : "\(title), \(n), \(toCheck) to check"
    }
}

public enum ThingGroups {
    public enum By: String, CaseIterable, Sendable { case place, height, kind }

    public static let somewhere = "Somewhere in the home"
    public static let heightOrder = ["floor", "knee", "waist", "chest", "head"]

    public static func group(_ things: [Thing], by: By) -> [ThingGroup] {
        switch by {
        case .place: byPlace(things)
        case .height: byHeight(things)
        case .kind: byKind(things)
        }
    }

    /// Rooms (most things first, the unknown room last), each split by furniture ("On or near the desk"), with
    /// what isn't near any furniture last ("Elsewhere in the room").
    public static func byPlace(_ things: [Thing]) -> [ThingGroup] {
        let rooms = Dictionary(grouping: things) { $0.room ?? somewhere }
        return rooms.sorted { a, b in
            (a.key == somewhere ? 1 : 0, -a.value.count, a.key) < (b.key == somewhere ? 1 : 0, -b.value.count, b.key)
        }.map { room, inRoom in
            let spots = Dictionary(grouping: inRoom) { $0.landmark ?? "" }
                .sorted { a, b in (a.key.isEmpty ? 1 : 0, -a.value.count, a.key) < (b.key.isEmpty ? 1 : 0, -b.value.count, b.key) }
                .map { landmark, here in
                    ThingGroup(id: "\(room)/\(landmark)",
                               title: landmark.isEmpty ? "Elsewhere in the room" : "On or near the \(landmark)",
                               things: here.sorted(by: Thing.listOrder))
                }
            return ThingGroup(id: room, title: room, things: inRoom.sorted(by: Thing.listOrder), spots: spots)
        }
    }

    /// The rooms to show maps for: rooms with things (most things first), then rooms scanned that have none yet
    /// (in the order given). "Somewhere in the home" isn't a room, so it has no map.
    public static func rooms(_ things: [Thing], scanned: [String] = []) -> [String] {
        let withThings = byPlace(things).map(\.title).filter { $0 != somewhere }
        var seen = Set(withThings)
        return withThings + scanned.filter { seen.insert($0).inserted }
    }

    /// Floor to head height, the five bands in that order.
    public static func byHeight(_ things: [Thing]) -> [ThingGroup] {
        let bands = Dictionary(grouping: things, by: \.heightBand)
        let order = heightOrder + bands.keys.filter { !heightOrder.contains($0) }.sorted()
        return order.compactMap { band in
            bands[band].map { ThingGroup(id: band, title: "\(band.prefix(1).uppercased())\(band.dropFirst()) height",
                                         things: $0.sorted(by: Thing.listOrder)) }
        }
    }

    /// By kind (keys, bags, books…), the biggest groups first; things of unknown kind last.
    public static func byKind(_ things: [Thing]) -> [ThingGroup] {
        Dictionary(grouping: things, by: \.kind)
            .sorted { a, b in (a.key == .unknown ? 1 : 0, -a.value.count, a.key.plural) < (b.key == .unknown ? 1 : 0, -b.value.count, b.key.plural) }
            .map { ThingGroup(id: $0.key.rawValue, title: $0.key.plural, things: $0.value.sorted(by: Thing.listOrder)) }
    }
}
