import ARKit
import Foundation
import Observation
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
    private let speech: any SpeechOutput
    private var task: Task<Void, Never>?

    init(room: String, home: String, source: any ArLabelsSource, locator: ARLocator, roomMap: @escaping (String) -> Data?,
         speech: any SpeechOutput) {
        self.room = room; self.home = home; self.source = source; self.locator = locator; self.roomMap = roomMap
        self.speech = speech
    }

    func start() {
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
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
            locator.start(roomMap: map)
            // ARKit says the room is recognised when tracking turns normal in the saved map
            for _ in 0..<50 {
                try await Task.sleep(for: .milliseconds(500))
                if locator.reading()?.tracking == .normal { break }
            }
            guard locator.reading()?.tracking == .normal else {
                return phase = .listOnly("I couldn't recognise \(room) from here, so here is the list.")
            }
            let tags = labels.map { (label: $0, tag: Self.tagImage($0)) }
            locator.showLabels(tags, floorY: found.floorY)
            phase = .showing
            let n = labels.count == 1 ? "1 thing" : "\(labels.count) things"
            speech.say("\(n) in \(room). Point at a label and double tap with two fingers to hear it.", interrupt: false)
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
