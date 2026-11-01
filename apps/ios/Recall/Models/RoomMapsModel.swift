import Foundation
import Observation
import RecallApplication
import RecallDomain

/// Each room's map for Find, loaded when its card first shows and kept until the list is refreshed. A room the Mac
/// has no map for (no processed scan yet, or the Mac unreachable) is just "not ready": Find never shows an error box
/// for a map.
@MainActor @Observable
final class RoomMapsModel {
    enum Entry: Equatable { case loading, ready(RobotMapPackage), notReady }

    private(set) var maps: [String: Entry] = [:]

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

    /// Pull to refresh: every map is asked for again as its card shows.
    func forget() { maps = [:] }
}
