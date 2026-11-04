import Foundation

/// One thing Recall found, placed in its room's saved AR map: what the label over the camera says, and its colour.
public struct ArLabel: Sendable, Equatable, Identifiable {
    /// green: Recall tells you about it; amber: it asks you to check; red: seen once, so it waits for you.
    public enum Mark: Sendable, Equatable { case told, check, seenOnce }

    public let id: String
    public let title: String
    public let place: String
    public let confidence: Double
    public let photos: Int?
    public let trusted: Bool
    public let needsReview: Bool
    /// in the ARKit frame of the scan whose room map the phone relocalises in
    public let position: SIMD3<Double>

    public init(id: String, title: String, place: String, confidence: Double, photos: Int?, trusted: Bool,
                needsReview: Bool, position: SIMD3<Double>) {
        self.id = id; self.title = title; self.place = place; self.confidence = confidence; self.photos = photos
        self.trusted = trusted; self.needsReview = needsReview; self.position = position
    }

    public var mark: Mark { !trusted ? .seenOnce : needsReview ? .check : .told }

    /// The tag's first line: "GREY BAG".
    public var headline: String { title.uppercased() }

    /// The tag's second line: "88% · 5 photos".
    public var detail: String {
        let sure = "\(Int((confidence * 100).rounded()))%"
        guard let photos else { return sure }
        return "\(sure) · \(photos == 1 ? "1 photo" : "\(photos) photos")"
    }

    /// What VoiceOver says: "Grey bag, near the desk, at knee height. 88 percent, seen in 5 photos. Recall tells you."
    public var spoken: String {
        let seen = photos.map { $0 == 1 ? ", seen in 1 photo" : ", seen in \($0) photos" } ?? ""
        let verdict = switch mark {
        case .told: "Recall tells you"
        case .check: "Check it"
        case .seenOnce: "Waits for you to confirm"
        }
        return "\(title.prefix(1).uppercased() + title.dropFirst()), \(place). \(Int((confidence * 100).rounded())) percent\(seen). \(verdict)."
    }
}

/// The labels for one room and the scan whose room map they are placed in.
public struct ArLabels: Sendable, Equatable {
    public let scanId: String
    public let room: String
    public let floorY: Double?
    public let labels: [ArLabel]
    public init(scanId: String, room: String, floorY: Double?, labels: [ArLabel]) {
        self.scanId = scanId; self.room = room; self.floorY = floorY; self.labels = labels
    }
}

/// What a spoken question settles on among the labels of the room the phone is in. Decided from the labels and the
/// words said, never from how the model phrased its answer: "where's my laptop?" with two laptops here asks which one,
/// "the black laptop" walks to it.
public enum ARPick: Sendable, Equatable {
    case walk(ArLabel)
    /// Several alike and the question doesn't say which.
    case which([ArLabel])
    /// Not one of the things labelled here.
    case elsewhere

    /// `thingId`: the thing the answer is about; `noun`: what it is ("laptop"), so alike things can be found.
    public static func settle(thingId: String?, noun: String?, question: String, labels: [ArLabel]) -> ARPick {
        guard let label = labels.first(where: { $0.id == thingId }) else { return .elsewhere }
        guard let noun = noun?.lowercased(), !noun.isEmpty else { return .walk(label) }
        let alike = labels.filter { $0.title.lowercased().hasSuffix(noun) }
        guard alike.count > 1 else { return .walk(label) }
        let said = Set(question.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let named = alike.filter { other in
            let words = other.title.lowercased().split(separator: " ").map(String.init).filter { !noun.contains($0) }
            return !words.isEmpty && words.allSatisfy(said.contains)
        }
        return named.count == 1 ? .walk(named[0]) : .which(named.isEmpty ? alike : named)
    }
}
