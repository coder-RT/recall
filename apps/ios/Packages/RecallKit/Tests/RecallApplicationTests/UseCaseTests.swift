import Foundation
import RecallDomain
import RecallTestSupport
import Testing
@testable import RecallApplication

private let keys = Thing.sample()

private func route(_ waypoints: [SIMD2<Double>], landmarks: Bool = false) -> Route {
    Route(sessionId: "gs", landmarksOnly: landmarks, reason: landmarks ? "no clear path" : nil,
          steps: [.init(clock: 12, metres: 2, say: landmarks ? "Your keys are on the desk." : "Straight ahead, then 2 metres.")],
          waypoints: waypoints, arriveSay: "Your keys should be in front of you, on the desk.")
}

@MainActor
private func guide(map: Data? = Data("map".utf8), locator: FakeLocator, service: FakeGuide)
    -> (GuideToThing, FakeSpeech, FakeHaptics, [GuideToThing.Phase]) {
    let speech = FakeSpeech(), haptics = FakeHaptics()
    var settings = GuideToThing.Settings()
    settings.locateTimeout = 2
    let g = GuideToThing(home: "flat", thing: keys, roomMap: map, locator: locator, guide: service, speech: speech,
                         haptics: haptics, clock: FakeClock(), settings: settings)
    return (g, speech, haptics, [])
}

@Suite("Guide to a thing") @MainActor
struct GuideToThingTests {
    @Test func relocalisesPlansFollowsAndArrives() async {
        let locator = FakeLocator(readings: [
            (.at(x: 0, z: 0), .limited),  // ARKit still matching the room
            (.at(x: 0, z: 0), .normal),  // matched
            (.at(x: 0, z: 0), .normal),  // the pose sent for planning
            (.at(x: 0, z: -1), .normal),
            (.at(x: 0, z: -1.8), .normal),  // corner reached: next leg is to the right
            (.at(x: 1.7, z: -2, yawDegrees: 90), .normal),
        ])
        let service = FakeGuide(routes: [route([[0, 0], [0, -2], [2, -2]])])
        let (g, speech, haptics, _) = guide(locator: locator, service: service)
        var phases: [GuideToThing.Phase] = []
        g.onChange = { phases.append($0) }
        await g.run()

        #expect(g.phase == .arrived("Found it. Your keys are at 12 o'clock, 40 centimetres away."))
        #expect(service.routeRequests.first?.tracking == .normal)
        #expect(phases.contains { if case .guiding(let c, _) = $0 { c.clock == 3 } else { false } })
        #expect(speech.lines.first == "Finding where you are. Hold the phone up at chest height and turn slowly.")
        #expect(speech.lines.contains("Straight ahead, then 2 metres."))
        #expect(speech.lines.contains("Your keys should be in front of you, on the desk. Hold the phone towards it. "
                                      + "I'm checking with the camera."))
        #expect(speech.lines.last == "Found it. Your keys are at 12 o'clock, 40 centimetres away.")  // the camera check has the last word
        #expect(service.verified.count == 1)
        #expect(haptics.events.last == "success")
        #expect(locator.stopped)
    }

    @Test func aRoomAlreadyRecognisedPlansAtOnce() async {
        // prepared while Find read the answer: the first reading is already normal
        let locator = FakeLocator(readings: [
            (.at(x: 0, z: 0), .normal), (.at(x: 0, z: 0), .normal), (.at(x: 0, z: -3.7), .normal),
        ])
        let service = FakeGuide(routes: [route([[0, 0], [0, -4]])])
        let (g, speech, _, _) = guide(locator: locator, service: service)
        await g.run()
        #expect(!speech.lines.contains { $0.hasPrefix("Finding where you are") })
        #expect(speech.lines.first == "Straight ahead, then 2 metres.")
        #expect(service.routeRequests.first?.tracking == .normal)
        #expect(g.phase == .arrived("Found it. Your keys are at 12 o'clock, 40 centimetres away."))
    }

    @Test func arrivingChecksWithTheCamera() async {
        func arrive(check: ArrivalCheck?, frame: ArrivalFrame? = .sample) async -> (GuideToThing, FakeSpeech, FakeHaptics, FakeGuide) {
            let locator = FakeLocator(readings: [(.at(x: 0, z: 0), .normal), (.at(x: 0, z: 0), .normal), (.at(x: 0, z: -3.7), .normal)])
            locator.frame = frame
            let service = FakeGuide(routes: [route([[0, 0], [0, -4]])])
            service.check = check
            let (g, speech, haptics, _) = guide(locator: locator, service: service)
            await g.run()
            return (g, speech, haptics, service)
        }
        let arrived = "Your keys should be in front of you, on the desk."
        var (g, speech, haptics, service) = await arrive(check: ArrivalCheck(outcome: .foundNearby, say: "Your keys are here, but moved."))
        #expect(g.phase == .arrived("Your keys are here, but moved.") && service.verified == [.sample])
        #expect(haptics.events.suffix(2) == ["success", "success"])  // arrived, then found
        (g, speech, haptics, _) = await arrive(check: ArrivalCheck(outcome: .notHere, say: "I can't see your keys from here."))
        #expect(g.phase == .arrived("I can't see your keys from here.") && haptics.events.last == "warning")
        (g, speech, _, service) = await arrive(check: nil)  // the Mac couldn't check
        #expect(g.phase == .arrived(arrived + " I couldn't check with the camera."))
        (g, _, _, service) = await arrive(check: ArrivalCheck(outcome: .confirmed, say: "x"), frame: nil)  // no camera frame
        #expect(g.phase == .arrived(arrived + " I couldn't check with the camera.") && service.verified.isEmpty)
        #expect(speech.lines.last == arrived + " I couldn't check with the camera.")
    }

    @Test func withoutARoomMapItGivesLandmarkDirections() async {
        let locator = FakeLocator(readings: [(.at(x: 3, z: 3), .normal)])
        let service = FakeGuide(routes: [route([], landmarks: true)])
        let (g, speech, _, _) = guide(map: nil, locator: locator, service: service)
        await g.run()
        #expect(g.phase == .landmarks("Your keys are on the desk."))
        #expect(service.routeRequests.first?.tracking == .limited)
        #expect(service.routeRequests.first?.pose == .identity)  // a pose outside the scan's world would mislead
        #expect(speech.lines.last == "Your keys are on the desk.")
    }

    @Test func anUnreadableMapCountsAsNoMap() async {
        let locator = FakeLocator(mapReadable: false, readings: [(.at(x: 0, z: 0), .normal)])
        let service = FakeGuide(routes: [route([], landmarks: true)])
        let (g, _, _, _) = guide(locator: locator, service: service)
        await g.run()
        #expect(service.routeRequests.first?.tracking == .limited)
    }

    @Test func noMatchInTimeFallsBackToLandmarks() async {
        let locator = FakeLocator(readings: [(.at(x: 0, z: 0), .limited)])
        let service = FakeGuide(routes: [route([], landmarks: true)])
        let (g, _, _, _) = guide(locator: locator, service: service)
        await g.run()
        #expect(service.routeRequests.first?.tracking == .limited)
        #expect(g.phase.isFinished)
    }

    @Test func aMacErrorEndsWithTheReason() async {
        let locator = FakeLocator(readings: [(.at(x: 0, z: 0), .normal)])
        let service = FakeGuide(error: RecallError.status(401))
        let (g, speech, _, _) = guide(locator: locator, service: service)
        await g.run()
        #expect(g.phase == .failed("The device key is wrong. Check it in Settings."))
        #expect(speech.lines.last == "The device key is wrong. Check it in Settings.")
    }

    @Test func leavingTheRouteGetsANewOne() async {
        let locator = FakeLocator(readings: [
            (.at(x: 0, z: 0), .normal), (.at(x: 0, z: 0), .normal),
            (.at(x: 2, z: -1), .normal),  // 2 m to the side of the first route
            (.at(x: 2, z: -1), .normal),  // the pose for the new plan
            (.at(x: 2, z: -2.7), .normal),
        ])
        let service = FakeGuide(routes: [route([[0, 0], [0, -4]]), route([[2, -1], [2, -3]])])
        let (g, speech, _, _) = guide(locator: locator, service: service)
        await g.run()
        #expect(service.routeRequests.count == 2)
        #expect(speech.lines.contains("You're off the route. Finding a new way."))
        #expect(g.phase == .arrived("Found it. Your keys are at 12 o'clock, 40 centimetres away."))
    }

    @Test func weakTrackingPausesDirectionsAndSaysWhyOnce() async {
        let locator = FakeLocator(readings: [
            (.at(x: 0, z: 0), .normal), (.at(x: 0, z: 0), .normal),
            (.at(x: 0, z: -1), .limited), (.at(x: 0, z: -1), .limited),
            (.at(x: 0, z: -3.7), .normal),
        ])
        let service = FakeGuide(routes: [route([[0, 0], [0, -4]])])
        let (g, speech, haptics, _) = guide(locator: locator, service: service)
        await g.run()
        #expect(speech.lines.filter { $0.hasPrefix("Tracking is weak") }.count == 1)
        #expect(haptics.events.contains("warning"))
        #expect(g.phase == .arrived("Found it. Your keys are at 12 o'clock, 40 centimetres away."))
    }
}

@Suite("Use cases") @MainActor
struct UseCaseTests {
    @Test func askNamesTheThingItFound() async throws {
        let ask = AskWhereIs(guide: FakeGuide(answer: Answer(text: "On the desk.", thingId: "obj_1", grounded: true)))
        let result = try await ask("where are my keys?", home: "flat", known: [keys])
        #expect(result.answer.text == "On the desk.")
        #expect(result.thing == keys)
        await #expect(throws: RecallError.self) { try await ask("   ", home: "flat", known: []) }
    }

    @Test func processingSaysWhenAScanIsReady() async {
        let speech = FakeSpeech()
        let scans = [Scan(id: "a", room: "Living room", createdAt: .now, grade: .good, directions: 10, frames: 50, state: .processing),
                     Scan(id: "b", room: "Hall", createdAt: .now, grade: .good, directions: 10, frames: 50, state: .processing),
                     Scan(id: "c", room: "Kitchen", createdAt: .now, grade: .good, directions: 10, frames: 50, state: .processed)]
        let track = TrackProcessing(processing: FakeProcessing(["a": (.processed, nil), "b": (.failed, "No frames.")]),
                                    memory: FakeHomeMemory(things: [keys, .sample("2", needsReview: true)]), speech: speech)
        let changes = await track(scans, home: "flat")
        #expect(changes == ["a": .init(.processed), "b": .init(.failed(reason: "No frames."))])
        #expect(speech.lines.contains("Living room is ready. 2 things found, 1 to check."))
    }

    @Test func aRescanSaysWhatChanged() async {
        let speech = FakeSpeech()
        var again = Scan(id: "r", room: "Living room", createdAt: .now, grade: .good, directions: 10, frames: 50,
                         state: .processing, alignedTo: "a")
        let moved = ScanChange(kind: .moved, objectId: "o1", label: "keys", color: "beige", from: "near the desk",
                               to: "on the shelf")
        let gone = ScanChange(kind: .gone, objectId: "o2", label: "bag", color: "grey", from: "near the desk")
        let track = TrackProcessing(processing: FakeProcessing(reports: ["r": ScanReport(.processed, changes: [moved, gone])]),
                                    memory: FakeHomeMemory(things: [keys]), speech: speech)
        let out = await track([again], home: "flat")
        #expect(out["r"] == .init(.processed, changes: [moved, gone]))
        #expect(speech.lines == ["Living room is ready. 2 changes: Your beige keys moved from near the desk to on the shelf. "
                                 + "Gone: your grey bag."])
        // nothing moved: said so
        again = Scan(id: "s", room: "Hall", createdAt: .now, grade: .good, directions: 10, frames: 50, state: .processing,
                     alignedTo: "h")
        _ = await TrackProcessing(processing: FakeProcessing(reports: ["s": ScanReport(.processed)]),
                                  memory: FakeHomeMemory(things: []), speech: speech)([again], home: "flat")
        #expect(speech.lines.last == "Hall is ready. Nothing has moved since the last scan.")
    }

    @Test func aRescanThatDidNotLineUpSaysItIsAFreshMap() async {
        let speech = FakeSpeech()
        let scan = Scan(id: "f", room: "Kitchen", createdAt: .now, grade: .good, directions: 10, frames: 50, state: .processing)
        let out = await TrackProcessing(processing: FakeProcessing(reports: ["f": ScanReport(.processed, fresh: true)]),
                                        memory: FakeHomeMemory(things: [keys]), speech: speech)([scan], home: "flat")
        #expect(out["f"]?.fresh == true)
        #expect(speech.lines == ["A fresh map of Kitchen. This walk didn't line up with your last scan, so I can't say what "
                                 + "moved this time. Kitchen is ready. 1 thing found."])
    }

    @Test func uploadNeedsSetupAndAManifest() async throws {
        let files = FakeEpisodeFiles(), uploads = FakeUploads()
        let upload = UploadScan(files: files, uploads: uploads, server: FakeScanServer(), speech: FakeSpeech())
        let scan = Scan(id: "s", room: "Kitchen", createdAt: .now, grade: .good, directions: 10, frames: 50)
        #expect(throws: RecallError.setup(.nothingSet)) { try upload(scan, connection: Connection(address: "", key: "", home: "")) }
        let ready = Connection(address: "mac:8000", key: "k", home: "flat")
        #expect(throws: RecallError.incompleteScan) { try upload(scan, connection: ready) }
        files.manifests["s"] = .sample(scan: "s")
        try upload(scan, connection: ready)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await uploads.started == ["s"])
    }

    @Test func pairingUpdatesTheConnection() throws {
        let store = FakeConnectionStore()
        let pair = PairDevice(store: store)
        let c = try pair(URL(string: "recall://pair?url=https://mac:8445&key=abc&home=loft")!)
        #expect(c == Connection(address: "https://mac:8445", key: "abc", home: "loft"))
        #expect(store.connection == c)
        #expect(try pair(URL(string: "https://example.com")!) == nil)
    }

    @Test func testConnectionSaysTheModel() async throws {
        #expect(try await TestConnection(check: FakeConnectionCheck(.success("baseten_spark_open")))()
                == "Connected. The Mac's Guide runs on baseten_spark_open.")
        await #expect(throws: RecallError.status(401)) {
            try await TestConnection(check: FakeConnectionCheck(.failure(.status(401))))()
        }
    }

    @Test func thingsLoadInListOrderAndCanBeCorrectedOrForgotten() async throws {
        let memory = FakeHomeMemory(things: [keys, .sample("2", label: "bag", needsReview: true)])
        let list = try await LoadThings(memory: memory)(home: "flat")
        #expect(list.map(\.id) == ["2", "obj_1"])  // unsure first
        try await CorrectThing(memory: memory)(keys, home: "flat", .from(name: "spare keys", color: "", heightCm: nil, note: ""))
        #expect(memory.corrections.first?.1.name == .set("spare keys"))
        try await ForgetThing(memory: memory)(keys, home: "flat")
        #expect(memory.things.map(\.id) == ["2"])
    }
}

@Suite("A scan waiting with no worker")
@MainActor
struct WorkerStoppedTests {
    private let waiting = Scan(id: "w", room: "Living room", createdAt: .now, grade: .good, directions: 12, frames: 160,
                               state: .processing)

    @Test func itSaysSoOnceWhenTheWorkerIsntRunning() async {
        let speech = FakeSpeech()
        let track = TrackProcessing(processing: FakeProcessing(reports: ["w": ScanReport(.processing, workerAlive: false)]),
                                    memory: FakeHomeMemory(), speech: speech)
        let out = await track([waiting], home: "flat")
        #expect(out["w"]?.workerStopped == true && out["w"]?.state == .processing)
        #expect(speech.lines == [Scan.workerStoppedMessage])
        var known = waiting
        known.workerStopped = true
        #expect(await track([known], home: "flat").isEmpty)  // already said: nothing new
        #expect(speech.lines.count == 1)
    }

    @Test func itClearsOnceTheWorkerRunsAgain() async {
        var known = waiting
        known.workerStopped = true
        let track = TrackProcessing(processing: FakeProcessing(reports: ["w": ScanReport(.processing, workerAlive: true)]),
                                    memory: FakeHomeMemory(), speech: FakeSpeech())
        #expect(await track([known], home: "flat")["w"]?.workerStopped == false)
    }

    @Test func aMacThatDoesntSayChangesNothing() async {
        let track = TrackProcessing(processing: FakeProcessing(reports: ["w": ScanReport(.processing)]),
                                    memory: FakeHomeMemory(), speech: FakeSpeech())
        #expect(await track([waiting], home: "flat").isEmpty)
    }
}
