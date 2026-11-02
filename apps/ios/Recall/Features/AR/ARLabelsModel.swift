import ARKit
import Foundation
import Observation
import RecallApplication
import RecallCapture
import RecallDomain
import SwiftUI

/// "See it in AR": recognise the room in its saved map, then float a label over everything Recall found there. The
/// labels are SAM 3.1's results from the Mac, placed by MapAnything's geometry; nothing is recognised on the phone.
@MainActor @Observable
final class ARLabelsModel {
    enum Phase: Equatable { case loading, locating, showing, listOnly(String), failed(String) }

    private(set) var phase = Phase.loading
    private(set) var labels: [ArLabel] = []
    var look = CameraLook.camera
    let room: String
    let locator: ARLocator

    private let source: any ArLabelsSource
    private let home: String
    private let roomMap: (String) -> Data?
    private let saveGrownMap: (String, Data) -> Void
    private let places: (any PlaceLocating)?
    private let speech: any SpeechOutput
    private let haptics: (any HapticsOutput)?
    private let clock: any Clock
    private var task: Task<Void, Never>?
    private var assist: PhotoAssist?

    /// Seconds before the list is shown instead, and how long the room is still looked for after that.
    static let listAfter = 25.0
    static let keepLooking = 120.0

    /// `places`: the Mac's photo matcher, to recognise the room alongside ARKit; `saveGrownMap`: keeps the map ARKit
    /// grew on this visit, so the next one recognises the room from here too.
    init(room: String, home: String, source: any ArLabelsSource, locator: ARLocator, roomMap: @escaping (String) -> Data?,
         saveGrownMap: @escaping (String, Data) -> Void = { _, _ in }, places: (any PlaceLocating)? = nil,
         speech: any SpeechOutput, haptics: (any HapticsOutput)? = nil, clock: any Clock = SystemClock()) {
        self.room = room; self.home = home; self.source = source; self.locator = locator; self.roomMap = roomMap
        self.saveGrownMap = saveGrownMap; self.places = places; self.speech = speech; self.haptics = haptics
        self.clock = clock
    }

    func start() {
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        assist?.cancel()
        locator.onMapGrown = nil
        locator.clearLabels()
        locator.stop()
    }

    /// What the camera points at, said aloud (Magic Tap).
    func sayInView() {
        guard let label = locator.labelInView() else {
            speech.say("Point the phone at a label.", interrupt: true)
            return
        }
        speech.say(label.spoken, interrupt: true)
    }

    private func run() async {
        do {
            let found = try await source.arLabels(home: home, room: room)
            labels = found.labels
            guard ARLocator.isSupported, let map = roomMap(found.scanId) else {
                return phase = .listOnly("The room map of this scan isn't on this iPhone, so here is the list.")
            }
            phase = .locating
            speech.say("Point the phone around \(room) so I can recognise it.", interrupt: true)
            let scan = found.scanId
            locator.onMapGrown = { [saveGrownMap] data in saveGrownMap(scan, data) }
            locator.start(roomMap: map)
            // the Mac's photo matcher helps alongside ARKit (named furniture to point at, a fix from a photo)
            if let places {
                let a = PhotoAssist(home: home, scan: scan, room: room, locator: locator, places: places, speech: speech,
                                    clock: clock)
                assist = a
                Task { await a.run() }
            }
            // recognised when tracking turns normal: ARKit matched the saved map, or two photo fixes agreed
            let started = clock.now()
            var late = false
            while locator.reading()?.tracking != .normal {
                let waited = clock.now().timeIntervalSince(started)
                if !late, waited >= Self.listAfter {
                    late = true  // the list now, but keep looking: the labels come on if the room is recognised
                    phase = .listOnly("I couldn't recognise \(room) from here yet, so here is the list. Still looking.")
                }
                if waited >= Self.listAfter + Self.keepLooking {
                    assist?.cancel()
                    return phase = .listOnly("I couldn't recognise \(room) from here, so here is the list.")
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            assist?.cancel()
            haptics?.tap()
            let tags = labels.map { (label: $0, tag: Self.tagImage($0)) }
            locator.showLabels(tags, floorY: found.floorY)
            phase = .showing
            let n = labels.count == 1 ? "1 thing" : "\(labels.count) things"
            let lead = late ? "Recognised \(room). " : ""
            speech.say("\(lead)\(n) in \(room). Point at a label and double tap with two fingers to hear it.",
                       interrupt: late)
        } catch is CancellationError {
        } catch {
            phase = .failed(UserMessage.explain(error))
        }
    }

    /// The tag as a picture: "GREY BAG" over "88% · 5 photos", dark glass with an edge in the label's colour.
    static func tagImage(_ label: ArLabel) -> UIImage {
        let renderer = ImageRenderer(content: ARTag(label: label))
        renderer.scale = 3
        return renderer.uiImage ?? UIImage()
    }
}

/// The scanner-style tag drawn into the AR view.
struct ARTag: View {
    let label: ArLabel
    var body: some View {
        let colour = Color(ARLocator.colour(label.mark))
        VStack(alignment: .leading, spacing: 2) {
            Text(label.headline).font(.system(size: 15, weight: .bold, design: .monospaced))
            Text(label.detail).font(.system(size: 12, weight: .medium, design: .monospaced)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(red: 0.05, green: 0.08, blue: 0.14).opacity(0.88), in: .rect(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(colour, lineWidth: 2))
        .overlay(alignment: .leading) { Rectangle().fill(colour).frame(width: 4).padding(.vertical, 2) }
    }
}
