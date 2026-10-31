import Foundation

/// One time the camera saw the thing: where, when, how sure, and which models found and placed it.
public struct Sighting: Sendable, Equatable, Identifiable {
    public let observationId: String
    public let label: String
    public let room: String
    public let seenAt: Date
    public let confidence: Double
    /// Still where the thing is now (a later scan hasn't moved it).
    public let current: Bool
    /// The Mac path of the camera's view of it, when the keyframe is kept.
    public let cropPath: String?
    public let segmenter: String?
    public let reconstructor: String?
    public var id: String { observationId }

    public init(observationId: String, label: String, room: String, seenAt: Date, confidence: Double, current: Bool,
                cropPath: String? = nil, segmenter: String? = nil, reconstructor: String? = nil) {
        self.observationId = observationId; self.label = label; self.room = room; self.seenAt = seenAt
        self.confidence = confidence; self.current = current; self.cropPath = cropPath
        self.segmenter = segmenter; self.reconstructor = reconstructor
    }

    /// "Seen in the Living room scan on 30 Oct at 04:21, 92% sure. Found by SAM 3.1; placed by MapAnything."
    public func spoken(timeZone: TimeZone = .current) -> String {
        var f = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: "en_GB"))
        f.timeZone = timeZone  // English words in an English sentence, the home's clock
        let sure = Int((confidence * 100).rounded())
        var line = "Seen in the \(room) scan on \(seenAt.formatted(f)), \(sure)% sure."
        if !current { line += " A later scan saw it somewhere else." }
        let models = [segmenter.map { "found by \(Sighting.modelName($0))" },
                      reconstructor.map { "placed by \(Sighting.modelName($0))" }].compactMap { $0 }
        if !models.isEmpty { line += " " + models.joined(separator: "; ").capitalizedFirst + "." }
        return line
    }

    /// Model ids as people say them: "sam-3.1" → "SAM 3.1", "map-anything-apache@00f9c24" → "MapAnything".
    static func modelName(_ id: String) -> String {
        if id.hasPrefix("sam-") { return "SAM " + id.dropFirst(4) }
        if id.hasPrefix("map-anything") { return "MapAnything" }
        if id == "arkit-depth" { return "the iPhone's LiDAR depth" }
        return id
    }
}

/// Why an answer said what it said.
public struct Evidence: Sendable, Equatable {
    public let question: String
    public let text: String
    public let model: String
    public let latencyMs: Int
    /// The tools the Guide called, in order ("find_object").
    public let tools: [String]
    public let sightings: [Sighting]

    public init(question: String, text: String, model: String, latencyMs: Int, tools: [String], sightings: [Sighting]) {
        self.question = question; self.text = text; self.model = model; self.latencyMs = latencyMs
        self.tools = tools; self.sightings = sightings
    }

    /// "Answered by Muse Spark Open from 1 sighting, in 2.3 seconds."
    public var summary: String {
        let model = self.model.contains("muse-spark-open") ? "Muse Spark Open" : self.model
        let n = sightings.count
        let secs = (Double(latencyMs) / 1000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en")))  // the sentence is English
        return "Phrased by \(model) from \(n) \(n == 1 ? "sighting" : "sightings"), in \(secs) seconds."
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
