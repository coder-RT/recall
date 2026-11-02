import Foundation
import Observation
import RecallApplication
import RecallDomain

/// Each room's map for Find, loaded when its card shows and kept until something changes it: a scan finishes
/// processing (a rescan redraws its room), or the user pulls to refresh. A room the Mac has no map for (no processed
/// scan yet, or the Mac unreachable) is just "not ready": Find never shows an error box for a map.
@MainActor @Observable
final class RoomMapsModel {
    enum Entry: Equatable { case loading, ready(RobotMapPackage), notReady }

    private(set) var maps: [String: Entry] = [:]
    /// Goes up each time the maps are forgotten, so cards already on screen ask again.
    private(set) var generation = 0

    private let source: any RoomMaps
    private let settings: SettingsModel

    init(source: any RoomMaps, settings: SettingsModel) {
        self.source = source; self.settings = settings
    }

    func load(_ room: String) async {
        guard maps[room] == nil || maps[room] == .notReady else { return }
        maps[room] = .loading
        do {
            maps[room] = .ready(try await source.roomMap(home: settings.connection.homeId, room: room))
        } catch let e where UserMessage.isCancellation(e) {
            maps[room] = nil  // the card scrolled away mid-request: ask again when it's back
        } catch {
            maps[room] = .notReady
        }
    }

    /// Every map is asked for again: cards on screen at once, the others when they show.
    func forget() {
        maps = [:]
        generation += 1
    }
}
