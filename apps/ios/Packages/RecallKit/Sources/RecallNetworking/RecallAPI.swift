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
        self.baseURL = baseURL
        self.deviceKey = deviceKey
        client = Client(serverURL: baseURL, transport: URLSessionTransport(), middlewares: [DeviceKey(key: deviceKey)])
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
