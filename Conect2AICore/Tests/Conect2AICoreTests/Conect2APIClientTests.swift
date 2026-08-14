import Foundation
import Testing
@testable import Conect2AICore

/// Intercepts every request of the stubbed URLSession so tests never touch the network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        // For POSTs, URLSession exposes the body as a stream, not httpBody.
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            request.httpBody = data
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeClient() -> Conect2APIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return Conect2APIClient(session: URLSession(configuration: config))
}

private let tripSummaryJSON = Data("""
{
  "time_session": "2024-12-19T08:28:08",
  "location": [[null, null], [-5.8429369, -35.1972234], [-5.8429369, -35.1972234]],
  "total_distance": 114.64130849740646,
  "total_time": 2619.999597,
  "speed": {
    "series": [null, 50, 50],
    "statistics": {"avg": 34.157076205287716, "max": 95.0}
  },
  "fuel_prediction": "Gasolina",
  "fuel_model_prediction_prob": 0.98,
  "emission_by_km": 35.565714081955385,
  "emission_classification": "A"
}
""".utf8)

@Suite(.serialized)
struct Conect2APIClientTests {

    @Test func loginSendsFormBodyAndStoresToken() async throws {
        let client = makeClient()
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/user-area/user/login")
            #expect(request.httpMethod == "POST")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            #expect(body.contains("username=morsinaldo%40ufrn.br"))
            #expect(body.contains("password=s3cret"))
            return (200, Data(#"{"access_token": "abc123", "token_type": "bearer"}"#.utf8))
        }
        let token = try await client.login(username: "morsinaldo@ufrn.br", password: "s3cret")
        #expect(token.accessToken == "abc123")
    }

    @Test func lastTripSummaryDecodesRealAPIShapeAndSendsBearerToken() async throws {
        let client = makeClient()
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"access_token": "trip-token", "token_type": "bearer"}"#.utf8))
        }
        try await client.login(username: "u", password: "p")

        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/user-area/trip/last-trip-summary")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer trip-token")
            return (200, tripSummaryJSON)
        }
        let trip = try await client.lastTripSummary()
        #expect(abs(trip.totalDistance - 114.6413) < 0.001)
        #expect(trip.speed.statistics.max == 95.0)
        #expect(trip.fuelPrediction == "Gasolina")
        #expect(trip.emissionClassification == "A")
    }

    @Test func requestsWithoutLoginFailWithNotAuthenticated() async throws {
        let client = makeClient()
        StubURLProtocol.handler = { _ in (200, tripSummaryJSON) }
        await #expect(throws: Conect2APIClient.APIError.notAuthenticated) {
            try await client.lastTripSummary()
        }
    }

    @Test func notFoundIsMappedToDedicatedError() async throws {
        let client = makeClient()
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"access_token": "t", "token_type": "bearer"}"#.utf8))
        }
        try await client.login(username: "u", password: "p")

        StubURLProtocol.handler = { _ in (404, Data()) }
        await #expect(throws: Conect2APIClient.APIError.notFound) {
            try await client.lastTripSummary()
        }
    }
}

struct TripSummaryFormatterTests {

    private func makeTrip() throws -> TripSummary {
        try JSONDecoder().decode(TripSummary.self, from: tripSummaryJSON)
    }

    @Test func spokenSummaryContainsDistanceDurationSpeedFuelAndEmission() throws {
        let summary = TripSummaryFormatter().spokenSummary(for: try makeTrip())
        #expect(summary.contains("114,6 quilômetros"))
        #expect(summary.contains("44 minutos"))
        #expect(summary.contains("média de 34"))
        #expect(summary.contains("máxima de 95"))
        #expect(summary.contains("Gasolina"))
        #expect(summary.contains("Classificação de emissão: A"))
    }

    @Test func durationFormatting() {
        let formatter = TripSummaryFormatter()
        #expect(formatter.duration(seconds: 20) == "menos de um minuto")
        #expect(formatter.duration(seconds: 60) == "1 minuto")
        #expect(formatter.duration(seconds: 3600) == "1 hora")
        #expect(formatter.duration(seconds: 5460) == "1 hora e 31 minutos")
    }
}
