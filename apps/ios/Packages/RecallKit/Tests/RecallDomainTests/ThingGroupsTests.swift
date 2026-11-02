import Foundation
import Testing
@testable import RecallDomain

private func thing(_ id: String, _ label: String, name: String? = nil, room: String? = "Living room",
                   landmark: String? = "desk", band: String = "waist", unsure: Bool = false,
                   confirmed: Bool = false) -> Thing {
    Thing(id: id, label: label, name: name, heightM: 0.8, heightBand: band, landmark: landmark, relation: "near",
          room: room, confidence: unsure ? 0.6 : 0.9, confirmed: confirmed, needsReview: unsure,
          seenAt: Date(timeIntervalSince1970: 0))
}

@Suite("What kind of thing")
struct ThingKindTests {
    @Test func labelsFromTheScan() {
        #expect(ThingKind.of(label: "keys") == .keys)
        #expect(ThingKind.of(label: "bag") == .handbag)
        #expect(ThingKind.of(label: "remote control") == .remote)
        #expect(ThingKind.of(label: "glasses") == .glasses)
        #expect(ThingKind.of(label: "headphones") == .headphones)
        #expect(ThingKind.of(label: "passport") == .passport)
        #expect(ThingKind.of(label: "plant") == .unknown)
        #expect(ThingKind.allCases.count == 16)
    }

    @Test func theUsersNameWinsAndSynonymsCount() {
        #expect(ThingKind.of(label: "bag", name: "Mum's purse") == .handbag)
        #expect(ThingKind.of(label: "bag", name: "school rucksack") == .backpack)
        #expect(ThingKind.of(label: "bottle", name: "my coffee cup") == .mug)
        #expect(ThingKind.of(label: "glasses", name: "Sunglasses") == .glasses)
        #expect(ThingKind.of(label: "book", name: "Grandma's") == .book)  // a name that says nothing: the label
        #expect(ThingKind.of(label: "charger", name: "spare cables") == .charger)  // plurals
    }

    @Test func notEveryWordInsideAnotherCounts() {
        #expect(ThingKind.of(label: "glass") == .unknown)  // a glass is not glasses
        #expect(ThingKind.of(label: "keyboard") == .unknown)  // "key" is a whole word only
        #expect(ThingKind.of(label: "stopwatch") == .unknown)
    }

    @Test func onlyASureThingGetsItsOwnIcon() {
        #expect(thing("1", "keys").iconKind == .keys)
        #expect(thing("2", "keys", unsure: true).iconKind == .unknown)  // the box
        #expect(thing("3", "keys", unsure: true, confirmed: true).iconKind == .keys)  // the user checked it
        #expect(thing("4", "keys", unsure: true).kind == .keys)  // its kind is still known for grouping
    }
}

@Suite("Grouping things")
struct ThingGroupsTests {
    let things = [
        thing("1", "keys", landmark: "desk"), thing("2", "bag", landmark: "desk", unsure: true),
        thing("3", "book", landmark: "shelf", band: "chest", unsure: true), thing("4", "bottle", landmark: nil, band: "floor"),
        thing("5", "mug", room: "Kitchen", landmark: "counter"), thing("6", "wallet", room: nil, landmark: nil),
    ]

    @Test func byRoomThenFurniture() {
        let rooms = ThingGroups.byPlace(things)
        #expect(rooms.map(\.title) == ["Living room", "Kitchen", "Somewhere in the home"])  // biggest first, unknown last
        let living = rooms[0]
        #expect(living.count == 4 && living.toCheck == 2)
        #expect(living.summary == "Living room, 4 things, 2 to check")
        #expect(living.spots.map(\.title) == ["On or near the desk", "On or near the shelf", "Elsewhere in the room"])
        #expect(living.spots[0].things.map(\.id) == ["2", "1"])  // unsure first, as in every list
        #expect(rooms[1].summary == "Kitchen, 1 thing")
    }

    @Test func byHeightFloorToHead() {
        let bands = ThingGroups.byHeight(things)
        #expect(bands.map(\.title) == ["Floor height", "Waist height", "Chest height"])
        #expect(bands[1].count == 4)
    }

    @Test func byKindBiggestFirst() {
        let kinds = ThingGroups.byKind(things + [thing("7", "purse")])
        #expect(kinds.first?.title == "Bags" && kinds.first?.count == 2)  // "bag" and "purse"
        #expect(kinds.map(\.title).contains("Keys"))
        #expect(ThingGroups.group(things, by: .kind) == ThingGroups.byKind(things))
    }

    @Test func roomsForMapsMostThingsFirstThenScannedOnes() {
        // "Somewhere in the home" has no map; a scanned room with nothing found yet still gets one, once
        #expect(ThingGroups.rooms(things, scanned: ["Hallway", "Kitchen"]) == ["Living room", "Kitchen", "Hallway"])
        #expect(ThingGroups.rooms([], scanned: ["Hallway", "Hallway"]) == ["Hallway"])
    }

    @Test func nothingToGroup() {
        #expect(ThingGroups.byPlace([]).isEmpty && ThingGroups.byHeight([]).isEmpty && ThingGroups.byKind([]).isEmpty)
    }
}
