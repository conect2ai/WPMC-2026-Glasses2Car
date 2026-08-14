import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for the Conect2AI research group API
/// (https://dashboard.conect2ai.dca.ufrn.br:8000).
///
/// Authentication uses the OAuth2 password flow: call ``login(username:password:)``
/// once, then the bearer token is attached to every subsequent request.
public actor Conect2APIClient {
    public enum APIError: Error, Equatable {
        case notAuthenticated
        case invalidResponse
        case unauthorized
        case notFound
        case http(Int)
        /// Body decoding failed; carries the decoder message and a body snippet.
        case decoding(String)
    }

    public static let defaultBaseURL = URL(string: "https://dashboard.conect2ai.dca.ufrn.br:8000")!

    private let baseURL: URL
    private let session: URLSession
    private var accessToken: String?

    public init(baseURL: URL = Conect2APIClient.defaultBaseURL,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// POST /v1/user-area/user/login — stores the bearer token for later calls.
    @discardableResult
    public func login(username: String, password: String) async throws -> TokenResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/user-area/user/login"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode([
            "grant_type": "password",
            "username": username,
            "password": password,
        ])
        let token: TokenResponse = try await send(request, authenticated: false)
        accessToken = token.accessToken
        return token
    }

    /// GET /v1/user-area/trip/last-trip-summary
    public func lastTripSummary(dependentId: Int? = nil) async throws -> TripSummary {
        var query: [URLQueryItem] = []
        if let dependentId {
            query.append(URLQueryItem(name: "dependent_id", value: String(dependentId)))
        }
        return try await send(get("/v1/user-area/trip/last-trip-summary", query: query))
    }

    /// GET /v1/user-area/trip/get-user-trips
    public func userTrips(dataCollector: String = "App2Car",
                          skip: Int? = nil,
                          limit: Int? = nil) async throws -> TripListResponse {
        var query = [URLQueryItem(name: "data_collector", value: dataCollector)]
        if let skip { query.append(URLQueryItem(name: "pagination_skip", value: String(skip))) }
        if let limit { query.append(URLQueryItem(name: "pagination_limit", value: String(limit))) }
        return try await send(get("/v1/user-area/trip/get-user-trips", query: query))
    }

    // MARK: - Smart Glass (test API)

    /// Decoded value plus the exact response body, for traceability logs.
    public struct APIResponse<T: Decodable & Sendable>: Sendable {
        public let value: T
        public let rawBody: Data
        /// URL + body + Authorization header + typical URLSession headers.
        public let requestBytesEstimate: Int

        public var rawString: String { String(data: rawBody, encoding: .utf8) ?? "" }
        /// Exact byte count of the response body (headers not included).
        public var responseBodyBytes: Int { rawBody.count }
    }

    /// GET /v1/user-area/trip/last-trip-summary with the raw body preserved —
    /// fallback source when there is no active trip to summarize.
    public func lastTripSummaryRaw(dependentId: Int? = nil) async throws -> APIResponse<TripSummary> {
        var query: [URLQueryItem] = []
        if let dependentId {
            query.append(URLQueryItem(name: "dependent_id", value: String(dependentId)))
        }
        return try await sendWithRaw(get("/v1/user-area/trip/last-trip-summary", query: query))
    }

    /// GET /v1/smart-glass/driver-behavior/ — behavior over the recent window.
    public func smartGlassDriverBehavior(latitude: Double? = nil,
                                         longitude: Double? = nil,
                                         windowSeconds: Int = 120) async throws -> APIResponse<DriverBehaviorResponse> {
        var query = [URLQueryItem(name: "window_seconds", value: String(windowSeconds))]
        if let latitude { query.append(URLQueryItem(name: "latitude", value: String(latitude))) }
        if let longitude { query.append(URLQueryItem(name: "longitude", value: String(longitude))) }
        return try await sendWithRaw(get("/v1/smart-glass/driver-behavior/", query: query))
    }

    /// GET /v1/smart-glass/emissions/ — real-time accumulated CO2 of the
    /// ongoing trip.
    public func smartGlassEmissions(latitude: Double? = nil,
                                    longitude: Double? = nil) async throws -> APIResponse<SmartGlassEmissions> {
        var query: [URLQueryItem] = []
        if let latitude { query.append(URLQueryItem(name: "latitude", value: String(latitude))) }
        if let longitude { query.append(URLQueryItem(name: "longitude", value: String(longitude))) }
        return try await sendWithRaw(get("/v1/smart-glass/emissions/", query: query))
    }

    /// POST /v1/smart-glass/trip/summary — aggregated trip summary (idempotent).
    public func smartGlassTripSummary(latitude: Double? = nil,
                                      longitude: Double? = nil,
                                      sendEmail: Bool = false) async throws -> APIResponse<SmartGlassTripSummary> {
        var body: [String: Any] = ["send_email": sendEmail]
        if let latitude { body["latitude"] = latitude }
        if let longitude { body["longitude"] = longitude }
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/smart-glass/trip/summary"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await sendWithRaw(request)
    }

    // MARK: - Internals

    private func get(_ path: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return URLRequest(url: components.url!)
    }

    private func sendWithRaw<T: Decodable & Sendable>(_ request: URLRequest,
                                                      authenticated: Bool = true) async throws -> APIResponse<T> {
        let (value, data): (T, Data) = try await sendReturningData(request, authenticated: authenticated)
        // Estimated wire size of the request: URL + body + auth header +
        // typical URLSession request-line/Host/Accept/User-Agent overhead.
        let urlBytes = request.url?.absoluteString.utf8.count ?? 0
        let bodyBytes = request.httpBody?.count ?? 0
        let authBytes = accessToken.map { $0.utf8.count + 24 } ?? 0
        let estimate = urlBytes + bodyBytes + authBytes + 350
        return APIResponse(value: value, rawBody: data, requestBytesEstimate: estimate)
    }

    private func send<T: Decodable>(_ request: URLRequest, authenticated: Bool = true) async throws -> T {
        try await sendReturningData(request, authenticated: authenticated).0
    }

    private func sendReturningData<T: Decodable>(_ request: URLRequest,
                                                 authenticated: Bool = true) async throws -> (T, Data) {
        var request = request
        if authenticated {
            guard let accessToken else { throw APIError.notAuthenticated }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw APIError.unauthorized
        case 404: throw APIError.notFound
        default: throw APIError.http(http.statusCode)
        }
        do {
            return (try JSONDecoder().decode(T.self, from: data), data)
        } catch {
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? "<binary>"
            throw APIError.decoding("\(error) — body: \(snippet)")
        }
    }

    private func formEncode(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}
