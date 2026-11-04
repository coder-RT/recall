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
/// (the same ARKit session, so nothing has to be recognised again), then the labels come back. It runs by voice: once
/// the room is recognised it asks what you're looking for and listens, and after a find it asks whether to go back.
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
    /// Walking back the way the person came, after a find.
    private(set) var isReturning = false
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
    /// The next thing heard answers "Do you want to go back, or are you done?".
    private var afterFound = false
    /// The next recording is thrown away: it was cut off by Done, a double tap or leaving the view.
    private var dropping = false
    private var followUp: Task<Void, Never>?

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
        stopListening()
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

    /// Tap to talk, tap to stop; a turn also ends when you stop talking, and after 15 s at most.
    func toggleListening() async {
        guard let asking else { return }
        if asking.voice.isRecording {
            asking.voice.stop()
            return
        }
        guard guide == nil else { return }
        await listen()
    }

    /// Opens the microphone; the tap on the phone tells someone who can't see the screen that it's their turn.
    private func listen() async {
        guard let asking, hearing == .idle, !asking.voice.isRecording else { return }
        haptics?.tap()
        heard = nil
        let started = await asking.voice.start(maxSeconds: 15, endOnSilence: true) { [weak self] wav in
            Task { await self?.heard(wav) }
        }
        hearing = started ? .listening : .idle
        if !started { speech.say(UserMessage.explain(RecallError.noMicrophone), interrupt: true) }
    }

    /// Ends a turn nobody wants the words of any more.
    private func stopListening() {
        followUp?.cancel()
        afterFound = false
        guard asking?.voice.isRecording == true else { return }
        dropping = true
        asking?.voice.stop()
    }

    /// Waits for a line to end: the speech engine says when; under VoiceOver only an estimate is possible.
    private func spoken(_ line: String) async {
        try? await clock.sleep(seconds: 0.2)
        let started = clock.now()
        while speech.isSpeaking, clock.now().timeIntervalSince(started) < 12 {
            try? await clock.sleep(seconds: 0.1)
        }
        if UIAccessibility.isVoiceOverRunning { try? await clock.sleep(seconds: SpokenLength.seconds(line)) }
    }

    /// Asks out loud, then listens without a tap.
    private func ask(_ line: String, interrupt: Bool = true) async {
        speech.say(line, interrupt: interrupt)
        await spoken(line)
        guard !Task.isCancelled else { return }
        await listen()
    }

    private func heard(_ wav: Data?) async {
        guard let asking, let wav, !wav.isEmpty, !dropping else {
            dropping = false
            hearing = .idle
            return
        }
        hearing = .thinking
        do {
            let question = try await asking.transcriber.transcribe(wav: wav).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty else {
                hearing = .idle
                return
            }
            heard = question
            if afterFound {
                afterFound = false
                switch FoundReply.read(question) {
                case .goBack:
                    hearing = .idle
                    return goBack()
                case .done:
                    hearing = .idle
                    endWalk()
                    return speech.say("You're welcome.", interrupt: true)
                case .question:
                    endWalk()  // the next thing: answered below like any question
                    heard = question
                }
            }
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
        stopListening()
        speech.say(line, interrupt: true)
        await spoken(line)
        locator.focus(label: thing.id)
        let walk = asking.makeGuide(thing, mapInUse)
        walk.onFinished = { [weak self] in self?.walkFinished($0) }
        guide = walk
        walk.start()
    }

    /// The walk reached its end. At the thing: ask what next. Back at the start: ask for the next thing.
    private func walkFinished(_ end: GuideToThing.Phase) {
        guard case .arrived(let said) = end else { return }
        if isReturning {
            endWalk()
            followUp = Task { [weak self] in await self?.ask("You're back. What else are you looking for?") }
            return
        }
        followUp = Task { [weak self] in
            await self?.spoken(said)
            guard !Task.isCancelled else { return }
            self?.afterFound = true
            await self?.ask("Do you want to go back, or are you done?")
        }
    }

    /// Back the way the person came, by voice or the Go back button.
    func goBack() {
        guard let guide, guide.canWalkBack else {
            return speech.say("I can't retrace this walk.", interrupt: true)
        }
        stopListening()
        isReturning = true
        guide.walkBack()
    }

    /// Closes the walk and brings the labels back.
    private func endWalk() {
        guide?.stop()
        guide = nil
        isReturning = false
        heard = nil
        locator.focus(label: nil)
    }

    /// The walk ended (Stop or Done; GuidePanel has stopped it): the labels are back for the next thing.
    func walkEnded() {
        stopListening()
        guide = nil
        isReturning = false
        heard = nil
        locator.focus(label: nil)
        guard phase == .showing else { return start() }  // it was still looking for the room: carry on
        followUp = Task { [weak self] in await self?.ask("What else are you looking for?") }
    }

    private func run() async {
        do {
            let found = try await source.arLabels(home: home, room: room)
            labels = found.labels
            guard ARLocator.isSupported, let map = roomMap(found.scanId) else {
                return phase = .listOnly("The room map of this scan isn't on this iPhone, so here is the list.")
            }
            phase = .locating
            speech.say("Scanning \(room). Point the phone around the room.", interrupt: true)
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
            await ask("\(lead)\(n) in \(room). What are you looking for?", interrupt: late)
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
