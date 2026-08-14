import Foundation

// MARK: - GET /v1/smart-glass/driver-behavior/

public struct DriverBehaviorResponse: Decodable, Sendable {
    public struct Window: Decodable, Sendable {
        public let seconds: Int
        public let windowStart: String?
        public let windowEnd: String?
        public let predominantBehavior: String?
        public let distribution: [String: Double]
        public let sampleCount: Int

        enum CodingKeys: String, CodingKey {
            case seconds
            case windowStart = "window_start"
            case windowEnd = "window_end"
            case predominantBehavior = "predominant_behavior"
            case distribution
            case sampleCount = "sample_count"
        }
    }

    public struct TripAggregate: Decodable, Sendable {
        public let timePerBehavior: [String: Double]
        public let sampleCount: Int

        enum CodingKeys: String, CodingKey {
            case timePerBehavior = "time_per_behavior"
            case sampleCount = "sample_count"
        }
    }

    public let timeSession: String?
    public let lastSampleAt: String?
    public let window: Window
    public let trip: TripAggregate?

    enum CodingKeys: String, CodingKey {
        case timeSession = "time_session"
        case lastSampleAt = "last_sample_at"
        case window
        case trip
    }
}

// MARK: - GET /v1/smart-glass/emissions/

/// Accumulated CO2 of the ongoing trip, computed in real time by the API.
public struct SmartGlassEmissions: Decodable, Sendable {
    public let timeSession: String?
    public let lastSampleAt: String?
    public let emissions: SmartGlassTripSummary.Emissions?

    enum CodingKeys: String, CodingKey {
        case timeSession = "time_session"
        case lastSampleAt = "last_sample_at"
        case emissions
    }
}

// MARK: - POST /v1/smart-glass/trip/summary

public struct SmartGlassTripSummary: Decodable, Sendable {
    public struct Speed: Decodable, Sendable {
        public let avg: Double?
        public let max: Double?
    }

    public struct Emissions: Decodable, Sendable {
        public let totalG: Double?
        public let emissionByKm: Double?
        public let classification: String?

        enum CodingKeys: String, CodingKey {
            case totalG = "total_g"
            case emissionByKm = "emission_by_km"
            case classification
        }
    }

    public let tripId: Int?
    public let timeSession: String?
    public let totalDistance: Double?
    public let totalTimeSeconds: Double?
    public let speed: Speed?
    public let fuelPrediction: String?
    public let emissions: Emissions?
    /// Seconds spent per behavior label over the whole trip.
    public let driverBehavior: [String: Double]?
    public let emailSent: Bool?

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case timeSession = "time_session"
        case totalDistance = "total_distance"
        case totalTimeSeconds = "total_time_seconds"
        case speed
        case fuelPrediction = "fuel_prediction"
        case emissions
        case driverBehavior = "driver_behavior"
        case emailSent = "email_sent"
    }
}
