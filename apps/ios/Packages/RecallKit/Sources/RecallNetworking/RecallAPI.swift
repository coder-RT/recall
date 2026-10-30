import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession
import RecallDomain

/// The Mac's API, through the client generated from services/api/resources/openapi.yaml (make gen-swift-client).
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
                        transport: transport, middlewares: [DeviceKey(key: deviceKey)])
    }

    public struct Plan: Sendable {
        public let partSize: Int
        public let parts: [(number: Int, path: String, received: Bool)]
        public let manifestPath: String
        public let completePath: String
    }

    public enum Status: String, Sendable { case uploading, uploaded, processing, processed, failed }

    public func health() async throws -> String {
        let r = try await client.getHealth()
        return try r.ok.body.json.llmProvider
    }

    public func createScan(scanId: String, homeId: String, room: String, size: Int, sha256: String, partSize: Int) async throws -> Plan {
        let body = Components.Schemas.ScanCreate(
            scanId: scanId, homeId: homeId, room: room,
            archive: .init(size: size, sha256: sha256, partSize: partSize))
        let r = try await client.createScan(body: .json(body))
        switch r {
        case .ok(let ok):
            let p = try ok.body.json
            return Plan(partSize: p.partSize, parts: p.parts.map { ($0.number, $0.url, $0.received) },
                        manifestPath: p.manifestUrl, completePath: p.completeUrl)
        case .unprocessableContent(let e): throw APIError.server(try e.body.json.detail ?? "The scan was refused.")
        case .undocumented(let code, _): throw APIError.status(code)
        }
    }

    /// PUT the manifest (domain type → the generated type through the same JSON, since both follow the spec).
    public func putManifest(scanId: String, manifest: Manifest) async throws -> Status {
        let json = try Manifest.encoder().encode(manifest)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let generated = try decoder.decode(Components.Schemas.Manifest.self, from: json)
        let r = try await client.putScanManifest(path: .init(scanId: scanId), body: .json(generated))
        switch r {
        case .ok(let ok): return Status(rawValue: try ok.body.json.status.rawValue) ?? .failed
        case .notFound: throw APIError.server("The Mac doesn't know this scan.")
        case .unprocessableContent(let e): throw APIError.server(try e.body.json.detail ?? "The manifest was refused.")
        case .undocumented(let code, _): throw APIError.status(code)
        }
    }

    public func complete(scanId: String) async throws -> (Status, String?) {
        let r = try await client.completeScan(path: .init(scanId: scanId))
        switch r {
        case .ok(let ok):
            let s = try ok.body.json
            return (Status(rawValue: s.status.rawValue) ?? .failed, s.detail)
        case .notFound: throw APIError.server("The Mac doesn't know this scan.")
        case .conflict(let e): throw APIError.server(try e.body.json.detail ?? "The scan isn't ready to complete.")
        case .undocumented(let code, _): throw APIError.status(code)
        }
    }

    public func scanStatus(scanId: String) async throws -> (Status, String?) {
        let r = try await client.getScan(path: .init(scanId: scanId))
        switch r {
        case .ok(let ok):
            let s = try ok.body.json
            return (Status(rawValue: s.status.rawValue) ?? .failed, s.detail)
        case .notFound: throw APIError.server("The Mac doesn't know this scan.")
        case .undocumented(let code, _): throw APIError.status(code)
        }
    }

    /// Everything memory holds for a home, with what the user corrected and what still needs checking.
    public func objects(homeId: String) async throws -> [RememberedObject] {
        let r = try await client.listObjects(path: .init(homeId: homeId))
        switch r {
        case .ok(let ok): return try ok.body.json.map(RememberedObject.init)
        case .notFound: return []  // no scan of this home processed yet
        case .undocumented(let code, _): throw APIError.status(code)
        }
    }

    /// Sends the user's fixes. A plain request because a correction must be able to send `null` (back to the
    /// measured value), which the generated client leaves out.
    public func correct(homeId: String, objectId: String, _ fix: ObjectFix) async throws {
        var req = URLRequest(url: baseURL.appending(path: "homes/\(homeId)/objects/\(objectId)"))
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(deviceKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: fix.json)
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw detail.map { APIError.server($0) } ?? APIError.status(code)
        }
    }

    public func remove(homeId: String, objectId: String) async throws {
        let r = try await client.removeObject(path: .init(homeId: homeId, objectId: objectId))
        switch r {
        case .noContent: return
        case .notFound: throw APIError.server("The Mac doesn't know this object any more.")
        case .undocumented(let code, _): throw APIError.status(code)
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
}

public enum APIError: Error, LocalizedError {
    case server(String), status(Int)
    public var errorDescription: String? {
        switch self {
        case .server(let s): return s
        case .status(401): return "The device key is wrong. Check it in Settings."
        case .status(503): return "The Mac is missing a setting. Check RECALL_DEVICE_KEY in its .env."
        case .status(let c): return "The Mac answered with an error (\(c))."
        }
    }
}

extension APIError {
    /// A plain sentence for any error a call can throw: the generated client's wrapper is opened up to the network
    /// error inside, and the common network failures say what to check.
    public static func explain(_ error: Error) -> String {
        var inner: Error = error
        if let e = error as? ClientError { inner = e.underlyingError }
        if let e = inner as? APIError { return e.localizedDescription }
        guard let url = inner as? URLError else { return inner.localizedDescription }
        switch url.code {
        case .notConnectedToInternet:
            return "The iPhone isn't allowed on the local network, or isn't on Wi-Fi. Turn on Settings, Privacy & Security, "
                + "Local Network, Recall, and check the iPhone is on the same Wi-Fi as the Mac. (Error -1009)"
        case .cannotConnectToHost:
            return "The Mac refused the connection. Check the Recall API is running and the port is 8000. (Error -1004)"
        case .timedOut:
            return "The Mac didn't answer. Check the address and that both are on the same Wi-Fi. (Error -1001)"
        case .cannotFindHost, .dnsLookupFailed:
            return "The address can't be found. Check the Mac address in Settings. (Error \(url.code.rawValue))"
        case .appTransportSecurityRequiresSecureConnection:
            return "iOS blocked plain http to this address. Use the Mac's local IP address or an https tunnel. (Error -1022)"
        default:
            return "\(url.localizedDescription) (Error \(url.code.rawValue))"
        }
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

/// Adds the shared device key (pairing, not a login) to every request.
struct DeviceKey: ClientMiddleware {
    let key: String
    func intercept(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
                   next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.authorization] = "Bearer \(key)"
        return try await next(request, body, baseURL)
    }
}

/// One remembered thing as the app shows it.
public struct RememberedObject: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let name: String?
    public let color: String?
    public let measuredColor: String?
    public let heightM: Double
    public let userHeightM: Double?
    public let heightBand: String
    public let landmark: String?
    public let relation: String?
    public let sizeCm: [Int]?
    public let note: String?
    public let confidence: Double
    public let confirmed: Bool
    public let needsReview: Bool
    public let seenAt: Date

    init(_ o: Components.Schemas.ObjectLocation) {
        id = o.objectId
        label = o.label
        name = o.corrections?.name
        color = o.color
        measuredColor = o.corrections?.color == nil ? o.color : nil
        heightM = o.position.count == 3 ? o.position[2] : 0
        userHeightM = o.corrections?.heightM
        heightBand = o.heightBand.rawValue
        landmark = o.landmark
        relation = o.relation?.rawValue
        sizeCm = o.sizeM?.map { Int(($0 * 100).rounded()) }
        note = o.corrections?.note
        confidence = o.confidence
        confirmed = o.corrections?.confirmed ?? false
        needsReview = o.needsReview ?? false
        seenAt = o.seenAt
    }

    /// What VoiceOver and the list say: "blue bag, on the desk, waist height".
    public var title: String { name ?? [color, label].compactMap { $0 }.joined(separator: " ") }
    public var place: String {
        let rel = (relation ?? "near").replacingOccurrences(of: "_", with: " ")
        let at = landmark.map { "\(rel) the \($0)" } ?? "in the room"
        return "\(at), \(heightBand) height"
    }
}

/// The fields a user changes; `.clear` sends null, which puts the measured value back.
public struct ObjectFix: Sendable {
    public enum Value<T: Sendable>: Sendable { case keep, set(T), clear }
    public var name: Value<String> = .keep
    public var color: Value<String> = .keep
    public var heightM: Value<Double> = .keep
    public var note: Value<String> = .keep
    public var confirmed: Bool?

    public init() {}

    var json: [String: Any] {
        var out: [String: Any] = [:]
        func put<T>(_ key: String, _ v: Value<T>) {
            switch v {
            case .keep: break
            case .set(let x): out[key] = x
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
