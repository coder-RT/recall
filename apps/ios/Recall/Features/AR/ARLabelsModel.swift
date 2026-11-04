import ARKit
import Foundation
import Observation
import RecallApplication
import RecallCapture
import RecallDomain
import SceneKit
import SwiftUI

/// "See it in AR": recognise the room in its saved map, then float a label over everything Recall found there. The
/// labels are SAM 3.1's results from the Mac, placed by MapAnything's geometry; nothing is recognised on the phone.
/// The view stays open: double tap a label, or say what you're looking for, and the walk there runs in this same camera
/// (the same ARKit session, so nothing has to be recognised again), then the labels come back.
@MainActor @Observable
final class ARLabelsModel {
    enum Phase: Equatable { case loading, locating, showing, listOnly(String), failed(String) }
    enum Hearing: Equatable { case idle, listening, thinking }

    /// What a question or a double tap needs: `things` to name what a label is, `makeGuide` to walk there in the map
    /// the labels are placed in. Nil in a preview of the list alone.
    struct Asking {
        let ask: AskInAR
        let transcriber: any Transcriber
        let voice: any VoiceInput
        let things: ThingsModel
        let makeGuide: @MainActor (Thing, (scan: String, data: Data)?) -> GuideModel
    }

    private(set) var phase = Phase.loading
    private(set) var labels: [ArLabel] = []
    private(set) var hearing = Hearing.idle
    /// What the person said, as Muse Voice Transcribe heard it: shown lightly over the camera so a wrong word is seen.
    private(set) var heard: String?
    /// The walk under way: its directions replace the list; the camera stays.
    private(set) var guide: GuideModel?
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
    private let asking: Asking?
    /// The room map the labels are placed in: a walk from this view must use the same one.
    private var mapInUse: (scan: String, data: Data)?
    /// The thing the last answer was about, so "the black one" means something.
    private var lastAbout: String?
    private var starting = false

    /// Seconds before the list is shown instead, and how long the room is still looked for after that.
    static let listAfter = 25.0
    static let keepLooking = 120.0

    /// `places`: the Mac's photo matcher, to recognise the room alongside ARKit; `saveGrownMap`: keeps the map ARKit
    /// grew on this visit, so the next one recognises the room from here too.
    init(room: String, home: String, source: any ArLabelsSource, locator: ARLocator, roomMap: @escaping (String) -> Data?,
         saveGrownMap: @escaping (String, Data) -> Void = { _, _ in }, places: (any PlaceLocating)? = nil,
         asking: Asking? = nil, speech: any SpeechOutput, haptics: (any HapticsOutput)? = nil,
         clock: any Clock = SystemClock()) {
        self.room = room; self.home = home; self.source = source; self.locator = locator; self.roomMap = roomMap
        self.saveGrownMap = saveGrownMap; self.places = places; self.speech = speech; self.haptics = haptics
        self.clock = clock; self.asking = asking
    }

    func start() {
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        assist?.cancel()
        guide?.stop()
        guide = nil
        if asking?.voice.isRecording == true { asking?.voice.stop() }
        locator.onMapGrown = nil
        locator.clearLabels()
        locator.stop()
    }

    /// Whether a label can be walked to right now (not while the room data loads, nor during a walk).
    var canGo: Bool { asking != nil && guide == nil && !labels.isEmpty }

    /// VoiceOver's two-finger double tap: directions to what the camera points at.
    func goToLabelInView() {
        guard canGo else { return }
        guard let label = locator.labelInView() else {
            speech.say("Point the phone at a label.", interrupt: true)
            return
        }
        go(to: label)
    }

    /// A double tap on the camera: directions to the label under the finger.
    func doubleTapped(at point: CGPoint, in view: SCNSceneRenderer) {
        guard canGo, phase == .showing else { return }
        guard let label = locator.label(at: point, in: view) else {
            speech.say("Double tap on a label.", interrupt: true)
            return
        }
        go(to: label)
    }

    /// Directions to a label, from the camera or the list.
    func go(to label: ArLabel) {
        guard canGo else { return }
        // the Mac plans no route to something seen in one photo: it waits for the owner to confirm it on Found
        guard label.mark != .seenOnce else {
            speech.say("Recall saw your \(label.title) only once, so it can't guide you there yet. It's \(label.place). "
                       + "Confirm it on Found to get directions.", interrupt: true)
            return
        }
        haptics?.tap()
        Task {
            await asking?.things.refreshIfNeeded(for: label.id)
            guard let thing = asking?.things.things.first(where: { $0.id == label.id }) else {
                speech.say("I can't reach the Mac for \(label.title) right now. It's \(label.place).", interrupt: true)
                return
            }
            await walk(to: thing, saying: "Directions to your \(label.title).")
        }
    }

    /// Tap to talk, tap to stop; the recording also ends by itself after 15 s, like Find.
    func toggleListening() async {
        guard let asking, guide == nil else { return }
        if asking.voice.isRecording {
            asking.voice.stop()
            return
        }
        haptics?.tap()
        heard = nil
        let started = await asking.voice.start(maxSeconds: 15) { [weak self] wav in
            Task { await self?.heard(wav) }
        }
        hearing = started ? .listening : .idle
        if !started { speech.say(UserMessage.explain(RecallError.noMicrophone), interrupt: true) }
    }

    private func heard(_ wav: Data?) async {
        guard let asking, let wav, !wav.isEmpty else {
            hearing = .idle
            return
        }
        hearing = .thinking
        do {
            let question = try await asking.transcriber.transcribe(wav: wav)
            heard = question
            speech.say(Acknowledgement.line(for: question, known: asking.things.things), interrupt: true)
            if !asking.things.loaded { await asking.things.refresh() }
            let outcome = try await asking.ask(question, home: home, known: asking.things.things, labels: labels,
                                               about: lastAbout)
            hearing = .idle
            switch outcome {
            case .walk(let thing, let say):
                lastAbout = thing.id
                await walk(to: thing, saying: say)
            case .which(let say), .answer(let say):
                speech.say(say, interrupt: true)
            }
        } catch {
            hearing = .idle
            speech.say(UserMessage.explain(error), interrupt: true)
        }
    }

    /// Says the line to the end, then walks: the first direction would cut it off otherwise.
    private func walk(to thing: Thing, saying line: String) async {
        guard let asking, guide == nil, !starting else { return }
        starting = true
        defer { starting = false }
        task?.cancel()  // still looking for the room: the guide does that itself now
        assist?.cancel()
        speech.say(line, interrupt: true)
        try? await clock.sleep(seconds: 0.2)
        let started = clock.now()
        while speech.isSpeaking, clock.now().timeIntervalSince(started) < 12 {
            try? await clock.sleep(seconds: 0.1)
        }
        locator.focus(label: thing.id)
        let walk = asking.makeGuide(thing, mapInUse)
        guide = walk
        walk.start()
    }

    /// The walk ended (Stop or Done; GuidePanel has stopped it): the labels are back for the next thing.
    func walkEnded() {
        guide = nil
        heard = nil
        locator.focus(label: nil)
        guard phase == .showing else { return start() }  // it was still looking for the room: carry on
        speech.say("Double tap another label, or tap Speak.", interrupt: true)
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
            mapInUse = (scan, map)
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
            speech.say("\(lead)\(n) in \(room). Double tap a label for directions, or tap Speak and say what you're looking for.",
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
