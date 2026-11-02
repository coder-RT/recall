import Foundation

/// What the Watch asks the iPhone. The Watch holds no key and never talks to the Mac: the phone does, and answers.
public enum WatchRequest: Sendable, Equatable, Codable {
    /// the things to pick from with the Digital Crown
    case things
    /// a picked thing: the way there
    case route(thingId: String)
    /// a spoken question; the audio travels as a file with this id
    case ask(audioFile: String)
}

/// A thing on the Watch's dial: short enough to say as the crown turns.
public struct WatchThing: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let place: String
    public init(id: String, title: String, place: String) { self.id = id; self.title = title; self.place = place }
}

/// The iPhone's answer to a WatchRequest.
public struct WatchReply: Sendable, Equatable, Codable {
    public var things: [WatchThing]?
    /// what to say: the Guide's grounded answer, or why it can't help
    public var say: String?
    public var route: CompassRoute?

    public init(things: [WatchThing]? = nil, say: String? = nil, route: CompassRoute? = nil) {
        self.things = things; self.say = say; self.route = route
    }
}
