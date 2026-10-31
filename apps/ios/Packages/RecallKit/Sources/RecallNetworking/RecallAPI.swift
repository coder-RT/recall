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
    public func ask(home: String, question: String) async throws -> Answer {
        let r = try await call { try await client.ask(body: .json(.init(homeId: home, question: question))) }
        switch r {
        case .ok(let ok):
            let a = try ok.body.json
            return Answer(text: a.text, thingId: a.objectId, grounded: a.grounded)
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
                         arriveSay: g.arriveSay)
        case .notFound(let e): throw RecallError.server(((try? e.body.json.detail) ?? nil) ?? "The Mac can't plan a route yet.")
        case .undocumented(let code, _): throw RecallError.status(code)
        }
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

extension RecallAPI: ConnectionCheck, ScanProcessing, ScanServer {
    /// The Mac answers (health) and accepts the key: a status call for a scan that doesn't exist answers "not found"
    /// only when the key was accepted.
    public func check() async throws -> String {
        let r = try await call { try await client.getHealth() }
        let provider = try r.ok.body.json.llmProvider
        do { _ = try await status(scan: "00000000-0000-4000-8000-000000000000") } catch RecallError.server {}
        return provider
    }

    public func status(scan: String) async throws -> (ScanStatus, detail: String?) {
        let r = try await call { try await client.getScan(path: .init(scanId: scan)) }
        switch r {
        case .ok(let ok):
            let s = try ok.body.json
            return (ScanStatus(rawValue: s.status.rawValue) ?? .failed, s.detail)
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
                  heightBand: o.heightBand.rawValue, landmark: o.landmark, relation: o.relation?.rawValue,
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
