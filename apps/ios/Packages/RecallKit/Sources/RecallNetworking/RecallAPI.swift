import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession
import RecallDomain

/// The Mac's API, through the client generated from services/api/resources/openapi.yaml (make gen-swift-client).
/// An adapter: it implements the domain's ports and maps the generated types to domain types, so nothing generated
/// leaves this module. Errors come out as RecallError or the URLError inside (never the generated wrapper).
public struct RecallAPI: Sendable {
    public let baseURL: URL
    let deviceKey: String
    let client: Client

    public init(baseURL: URL, deviceKey: String) {
        self.init(baseURL: baseURL, deviceKey: deviceKey, transport: URLSessionTransport())
    }

    init(baseURL: URL, deviceKey: String, transport: any ClientTransport) {
        self.baseURL = baseURL
        self.deviceKey = deviceKey
        client = Client(serverURL: baseURL, configuration: .init(dateTranscoder: RFC3339Dates()),
                        transport: transport, middlewares: [BearerKey(key: deviceKey)])
    }

    /// Runs a generated-client call with its wrapper error opened up to the error inside.
    func call<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch let e as ClientError { throw e.underlyingError }
    }

    /// A plain request with the device key, for the calls the generated client can't make (multipart, JSON nulls).
    func request(_ path: String, method: String, contentType: String, body: Data) -> URLRequest {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.setValue("Bearer \(deviceKey)", forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }

    /// Sends a plain request; non-200 answers become RecallError with the Mac's `detail` when it gives one.
    func send(_ req: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200..<300).contains(code) else {
            throw (json["detail"] as? String).map { RecallError.server($0) } ?? RecallError.status(code)
        }
        return json
    }
}

// MARK: HomeMemory

extension RecallAPI: HomeMemory {
    public func things(home: String) async throws -> [Thing] {
        let r = try await call { try await client.listObjects(path: .init(homeId: home)) }
        switch r {
        case .ok(let ok): return try ok.body.json.map(Thing.init)
        case .notFound: return []  // no scan of this home processed yet
        case .undocumented(let code, _): throw RecallError.status(code)
        }
    }

    /// A plain request because a correction must be able to send `null` (back to the measured value), which the
    /// generated client leaves out.
    public func correct(home: String, thing: String, _ correction: Correction) async throws {
        let body = try JSONSerialization.data(withJSONObject: correction.json)
        _ = try await send(request("homes/\(home)/objects/\(thing)", method: "PATCH", contentType: "application/json", body: body))
    }

    public func forget(home: String, thing: String) async throws {
        let r = try await call { try await client.removeObject(path: .init(homeId: home, objectId: thing)) }
        switch r {
        case .noContent: return
        case .notFound: throw RecallError.server("The Mac doesn't know this thing any more.")
        case .undocumented(let code, _): throw RecallError.status(code)
        }
    }
}

// MARK: GuideService, Transcriber

extension RecallAPI: GuideService, Transcriber {
    public func ask(home: String, question: String, about: String?) async throws -> Answer {
        let r = try await call { try await client.ask(body: .json(.init(homeId: home, question: question, about: about))) }
        switch r {
        case .ok(let ok):
            let a = try ok.body.json
            return Answer(text: a.text, thingId: a.objectId, grounded: a.grounded, answerId: a.answerId)
        case .serviceUnavailable: throw RecallError.server("The Guide isn't available right now. Try again in a moment.")
        case .undocumented(let code, _): throw RecallError.status(code)
        }
    }

    public func route(home: String, to thing: String, from pose: Pose, tracking: TrackingState) async throws -> Route {
        let body = Components.Schemas.GuidanceRequest(homeId: home, objectId: thing, pose: .init(matrix: pose.columnMajor),
                                                      tracking: .init(rawValue: tracking.rawValue) ?? .limited)
        let r = try await call { try await client.startGuidance(body: .json(body)) }
        switch r {
        case .ok(let ok):
            let g = try ok.body.json
            return Route(sessionId: g.sessionId, landmarksOnly: g.mode == .landmarks, reason: g.reason,
                         steps: g.steps.map { .init(clock: $0.clock, metres: $0.metres, say: $0.say) },
                         waypoints: (g.pathArkit ?? []).compactMap { $0.count == 2 ? SIMD2($0[0], $0[1]) : nil },
                         arriveSay: g.arriveSay,
                         target: g.targetArkit.flatMap { $0.count == 3 ? SIMD3($0[0], $0[1], $0[2]) : nil },
                         bearingDeg: g.bearingDeg, floorY: g.floorYArkit)
        case .notFound(let e): throw RecallError.server(((try? e.body.json.detail) ?? nil) ?? "The Mac can't plan a route yet.")
        case .undocumented(let code, _): throw RecallError.status(code)
        }
    }

    /// The arrival check: the photo, the depth and the pose as multipart (VerificationRequest.yaml).
    public func verify(session: String, frame: ArrivalFrame) async throws -> ArrivalCheck {
        let boundary = "recall-\(UUID().uuidString)"
        var body = Data()
        func part(_ name: String, filename: String?, type: String?, _ data: Data) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"".utf8))
            if let filename { body.append(Data("; filename=\"\(filename)\"".utf8)) }
            body.append(Data("\r\n".utf8))
            if let type { body.append(Data("Content-Type: \(type)\r\n".utf8)) }
            body.append(Data("\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }
        part("image", filename: "arrival.jpg", type: "image/jpeg", frame.jpeg)
        part("depth", filename: "depth.bin", type: "application/octet-stream", frame.depthMM)
        part("pose", filename: nil, type: nil, frame.poseJSON)
        body.append(Data("--\(boundary)--\r\n".utf8))
        let json = try await send(request("guidance/sessions/\(session)/verify", method: "POST",
                                          contentType: "multipart/form-data; boundary=\(boundary)", body: body))
        guard let raw = json["outcome"] as? String, let outcome = ArrivalCheck.Outcome(rawValue: raw),
              let say = json["say"] as? String else { throw RecallError.server("The Mac sent no arrival check.") }
        return ArrivalCheck(outcome: outcome, say: say)
    }

    /// Muse Voice Transcribe on the Mac: mono 16-bit PCM WAV at 16 kHz, as multipart (it carries a file).
    public func transcribe(wav: Data) async throws -> String {
        let boundary = "recall-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"question.wav\"\r\n".utf8)
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let json = try await send(request("transcribe", method: "POST", contentType: "multipart/form-data; boundary=\(boundary)",
                                          body: body))
        guard let text = json["text"] as? String else { throw RecallError.server("The Mac sent no transcript.") }
        return text
    }
}

// MARK: ConnectionCheck, ScanProcessing, ScanServer

extension RecallAPI: PrivacySource {
    public func privacy() async throws -> PrivacyStatus {
        let r = try await call { try await client.getPrivacy() }
        switch r {
        case .ok(let ok):
            let p = try ok.body.json
            return PrivacyStatus(storedOn: p.storedOn,
                                 sent: p.sent.map { DataFlow(what: $0.what, to: $0.to, when: $0.when, onThisMac: $0.onThisMac ?? false) },
                                 robotAccess: p.robotAccess, auditDays: p.auditDays)
        case .undocumented(let code, _): throw RecallError.status(code)
        }
    }
}

extension RecallAPI: ConnectionCheck, ScanProcessing, ScanServer {
    /// The Mac answers (health) and accepts the key: a status call for a scan that doesn't exist answers "not found"
    /// only when the key was accepted.
    public func check() async throws -> String {
        let r = try await call { try await client.getHealth() }
        let provider = try r.ok.body.json.llmProvider
        do { _ = try await status(scan: "00000000-0000-4000-8000-000000000000") } catch RecallError.server {}
        return provider
    }

    public func erase(scan: String) async throws {
        let r = try await call { try await client.eraseScan(path: .init(scanId: scan)) }
        switch r {
        case .noContent, .notFound: return  // gone already is fine
        case .conflict(let e):
            throw RecallError.server(try e.body.json.detail ?? "The Mac is still processing this scan.")
        case .undocumented(let code, _): throw RecallError.status(code)
        }
    }

    public func status(scan: String) async throws -> ScanReport {
        let r = try await call { try await client.getScan(path: .init(scanId: scan)) }
        switch r {
        case .ok(let ok):
            let s = try ok.body.json
            let changes = (s.changes ?? []).map { c in
                ScanChange(kind: ScanChange.Kind(rawValue: c.kind.rawValue) ?? .moved, objectId: c.objectId, label: c.label,
                           name: c.name, color: c.color, from: c.from, to: c.to)
            }
            return ScanReport(ScanStatus(rawValue: s.status.rawValue) ?? .failed, detail: s.detail, changes: changes,
                              fresh: s.fresh ?? false)
        case .notFound: throw RecallError.server("The Mac doesn't know this scan.")
        case .undocumented(let code, _): throw RecallError.status(code)
        }
    }

    public func createScan(scan: String, home: String, room: String, size: Int, sha256: String, partSize: Int) async throws -> UploadPlan {
        let body = Components.Schemas.ScanCreate(scanId: scan, homeId: home, room: room,
                                                 archive: .init(size: size, sha256: sha256, partSize: partSize))
        let r = try await call { try await client.createScan(body: .json(body)) }
        switch r {
        case .ok(let ok):
            return UploadPlan(parts: try ok.body.json.parts.map { .init(number: $0.number, path: $0.url, received: $0.received) })
        case .unprocessableContent(let e): throw RecallError.server(try e.body.json.detail ?? "The scan was refused.")
        case .undocumented(let code, _): throw RecallError.status(code)
        }
    }

    /// The part upload as a plain request, for the background URLSession (which needs a request and a file).
    public func partRequest(path: String, sha256: String) -> URLRequest {
        var req = URLRequest(url: path.hasPrefix("http") ? URL(string: path)! : baseURL.appending(path: path))
        req.httpMethod = "PUT"
        req.setValue("Bearer \(deviceKey)", forHTTPHeaderField: "Authorization")
        req.setValue(sha256, forHTTPHeaderField: "X-Content-SHA256")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        return req
    }

    /// The manifest (domain type → the generated type through the same JSON, since both follow the spec).
    public func putManifest(scan: String, manifest: Manifest) async throws {
        let json = try Manifest.encoder().encode(manifest)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let generated = try decoder.decode(Components.Schemas.Manifest.self, from: json)
        let r = try await call { try await client.putScanManifest(path: .init(scanId: scan), body: .json(generated)) }
        switch r {
        case .ok: return
        case .notFound: throw RecallError.server("The Mac doesn't know this scan.")
        case .unprocessableContent(let e): throw RecallError.server(try e.body.json.detail ?? "The manifest was refused.")
        case .undocumented(let code, _): throw RecallError.status(code)
        }
    }

    public func complete(scan: String) async throws -> (ScanStatus, detail: String?) {
        let r = try await call { try await client.completeScan(path: .init(scanId: scan)) }
        switch r {
        case .ok(let ok):
            let s = try ok.body.json
            return (ScanStatus(rawValue: s.status.rawValue) ?? .failed, s.detail)
        case .notFound: throw RecallError.server("The Mac doesn't know this scan.")
        case .conflict(let e): throw RecallError.server(try e.body.json.detail ?? "The scan isn't ready to complete.")
        case .undocumented(let code, _): throw RecallError.status(code)
        }
    }
}

// MARK: mapping

extension Thing {
    init(_ o: Components.Schemas.ObjectLocation) {
        self.init(id: o.objectId, label: o.label, name: o.corrections?.name, color: o.color,
                  measuredColor: o.corrections?.color == nil ? o.color : nil,
                  heightM: o.position.count == 3 ? o.position[2] : 0, userHeightM: o.corrections?.heightM,
                  heightBand: o.heightBand.rawValue, landmark: o.landmark, relation: o.relation?.rawValue, room: o.room,
                  sizeCm: o.sizeM?.map { Int(($0 * 100).rounded()) }, note: o.corrections?.note, confidence: o.confidence,
                  confirmed: o.corrections?.confirmed ?? false, needsReview: o.needsReview ?? false, seenAt: o.seenAt)
    }
}

extension Correction {
    /// The PATCH body: kept fields are left out, cleared ones are sent as null.
    var json: [String: Any] {
        var out: [String: Any] = [:]
        func put<T>(_ key: String, _ edit: Edit<T>) {
            switch edit {
            case .keep: break
            case .set(let v): out[key] = v
            case .clear: out[key] = NSNull()
            }
        }
        put("name", name)
        put("color", color)
        put("height_m", heightM)
        put("note", note)
        if let confirmed { out["confirmed"] = confirmed }
        return out
    }
}

/// Adds the shared device key (pairing, not a login) to every request.
struct BearerKey: ClientMiddleware {
    let key: String
    func intercept(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
                   next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.authorization] = "Bearer \(key)"
        return try await next(request, body, baseURL)
    }
}

/// RFC 3339 times with or without fractional seconds: the Mac sends `2026-10-30T03:21:01.123632Z`, which the
/// runtime's default (no fractions) refuses.
struct RFC3339Dates: DateTranscoder {
    func encode(_ date: Date) throws -> String { Self.formatter(fractions: false).string(from: date) }

    func decode(_ text: String) throws -> Date {
        for fractions in [true, false] {
            if let date = Self.formatter(fractions: fractions).date(from: text) { return date }
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not an RFC 3339 time: \(text)"))
    }

    private static func formatter(fractions: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = fractions ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return f
    }
}

// MARK: Evidence

extension RecallAPI: EvidenceSource {
    public func evidence(answer: String) async throws -> Evidence {
        let r = try await call { try await client.getEvidence(path: .init(answerId: answer)) }
        switch r {
        case .ok(let ok):
            let e = try ok.body.json
            let sightings = e.sightings.map { s in
                let prov = s.scan.provenance?.additionalProperties.value ?? [:]
                return Sighting(observationId: s.observationId, label: s.label, room: s.scan.room, seenAt: s.seenAt,
                                confidence: s.confidence, current: s.current, cropPath: s.cropUrl,
                                segmenter: prov["segmenter"] as? String, reconstructor: prov["reconstructor"] as? String)
            }
            return Evidence(question: e.answer.question, text: e.answer.text, model: e.answer.model,
                            latencyMs: e.answer.latencyMs, tools: e.steps.compactMap(\.tool), sightings: sightings)
        case .notFound: throw RecallError.server("The Mac no longer has this answer's evidence.")
        case .undocumented(let code, _): throw RecallError.status(code)
        }
    }

    public func crop(path: String) async throws -> Data {
        guard let id = path.split(separator: "/").dropLast().last.map(String.init) else { throw RecallError.status(404) }
        let r = try await call { try await client.getSightingCrop(path: .init(observationId: id)) }
        switch r {
        case .ok(let ok): return try await Data(collecting: ok.body.jpeg, upTo: 5 * 1024 * 1024)
        case .notFound: throw RecallError.server("No camera view is kept for this sighting.")
        case .undocumented(let code, _): throw RecallError.status(code)
        }
    }
}

// MARK: RobotSharing

extension RecallAPI: RobotSharing {
    public func robotAccess() async throws -> RobotAccessStatus {
        Self.status(try await send(request("sharing", method: "GET", contentType: "application/json", body: Data())))
    }

    public func setRobotAccess(_ on: Bool) async throws -> RobotAccessStatus {
        let body = try JSONSerialization.data(withJSONObject: ["robot_access": on])
        return Self.status(try await send(request("sharing", method: "PUT", contentType: "application/json", body: body)))
    }

    public func activity(limit: Int) async throws -> [AuditEntry] {
        var req = request("audit", method: "GET", contentType: "application/json", body: Data())
        req.url = req.url.flatMap { URL(string: $0.absoluteString + "?limit=\(limit)") }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RecallError.status((response as? HTTPURLResponse)?.statusCode ?? 0) }
        return Self.entries(data)
    }

    static func entries(_ data: Data) -> [AuditEntry] {
        let rows = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return rows.compactMap { r in
            guard let id = r["id"] as? String, let at = r["at"] as? String,
                  let date = iso.date(from: at) ?? plain.date(from: at) else { return nil }
            let detail = (r["detail"] as? [String: Any] ?? [:]).mapValues { v -> String in
                if let b = v as? Bool { return b ? "true" : "false" }
                return "\(v)"
            }
            return AuditEntry(id: id, at: date, actor: r["actor"] as? String ?? "unknown", action: r["action"] as? String ?? "",
                              outcome: r["outcome"] as? String ?? "ok", detail: detail)
        }
    }

    static func status(_ j: [String: Any]) -> RobotAccessStatus {
        RobotAccessStatus(on: j["robot_access"] as? Bool ?? false, a2aURL: j["a2a_url"] as? String ?? "",
                          agentCardURL: j["agent_card_url"] as? String ?? "", exportURL: j["export_url"] as? String ?? "")
    }

    /// GET /homes/{id}/robot-export, turned back into the files a ROS 2 robot loads.
    public func robotMap(home: String) async throws -> RobotMapPackage {
        let j = try await send(request("homes/\(home)/robot-export", method: "GET", contentType: "application/json", body: Data()))
        return try Self.package(j)
    }

    static func package(_ j: [String: Any]) throws -> RobotMapPackage {
        guard let m = j["map"] as? [String: Any], let b64 = m["pgm_base64"] as? String, let pgm = Data(base64Encoded: b64),
              let resolution = m["resolution"] as? Double, let origin = m["origin"] as? [Double], origin.count == 3,
              let map = RobotMap(pgm: pgm, resolution: resolution, origin: (origin[0], origin[1]))
        else { throw RecallError.server("The Mac sent an unreadable robot map.") }
        let objects = j["objects"] as? [[String: Any]] ?? []
        let things = objects.compactMap { o -> RobotMapPackage.Thing? in
            guard let label = o["label"] as? String, let p = o["position"] as? [Double], p.count >= 2 else { return nil }
            return .init(label: label, color: o["color"] as? String, x: p[0], y: p[1])
        }
        // map.yaml as Nav2's map server reads it; objects.json is the export without the map and the room outline
        let yaml = """
        image: map.pgm
        mode: \(m["mode"] as? String ?? "trinary")
        resolution: \(resolution)
        origin: [\(origin[0]), \(origin[1]), \(origin[2])]
        negate: \(m["negate"] as? Int ?? 0)
        occupied_thresh: \(m["occupied_thresh"] as? Double ?? 0.65)
        free_thresh: \(m["free_thresh"] as? Double ?? 0.25)

        """
        var doc = j
        doc["map"] = nil
        doc["room_model"] = nil
        let objectsJSON = try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
        let roomJSON = try JSONSerialization.data(withJSONObject: j["room_model"] ?? [:], options: [.prettyPrinted, .sortedKeys])
        return RobotMapPackage(room: j["room"] as? String ?? "Room", map: map, things: things,
                               files: ["map.pgm": pgm, "map.yaml": Data(yaml.utf8), "objects.json": objectsJSON,
                                       "room.json": roomJSON])
    }
}
