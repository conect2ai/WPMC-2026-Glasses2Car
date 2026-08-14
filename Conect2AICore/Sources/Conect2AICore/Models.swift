import Foundation

/// Response of POST /v1/user-area/user/login (OAuth2 password flow).
public struct TokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
    }
}

public struct SeriesStatistics: Decodable, Sendable {
    public let min: Double?
    public let avg: Double?
    public let max: Double?
}

/// A sensor series as returned by the trip endpoints (values may contain nulls).
public struct SensorSeries: Decodable, Sendable {
    public let series: [Double?]
    public let statistics: SeriesStatistics
}

/// Response of GET /v1/user-area/trip/last-trip-summary.
public struct TripSummary: Decodable, Sendable {
    public let timeSession: String
    /// GPS points; individual coordinates may be null before the first GPS fix.
    public let location: [[Double?]]?
    public let totalDistance: Double
    public let totalTime: Double
    public let speed: SensorSeries
    public let fuelPrediction: String?
    public let fuelModelPredictionProb: Double?
    public let emissionByKm: Double?
    public let emissionClassification: String?

    enum CodingKeys: String, CodingKey {
        case timeSession = "time_session"
        case location
        case totalDistance = "total_distance"
        case totalTime = "total_time"
        case speed
        case fuelPrediction = "fuel_prediction"
        case fuelModelPredictionProb = "fuel_model_prediction_prob"
        case emissionByKm = "emission_by_km"
        case emissionClassification = "emission_classification"
    }
}

public struct TripVehicle: Decodable, Sendable {
    public let id: Int
    public let brand: String
    public let model: String
    public let year: Int
    public let version: String?
    public let category: String?
}

/// One item of GET /v1/user-area/trip/get-user-trips.
public struct TripListItem: Decodable, Sendable {
    public let timeSession: String
    public let collectorId: Int?
    public let vehicle: TripVehicle?
    public let vin: String?
    public let tripDuration: Double?
    public let fuelPrediction: String?

    enum CodingKeys: String, CodingKey {
        case timeSession = "time_session"
        case collectorId = "collector_id"
        case vehicle
        case vin = "VIN"
        case tripDuration = "trip_duration"
        case fuelPrediction = "fuel_prediction"
    }
}

/// Response of GET /v1/user-area/trip/get-user-trips.
public struct TripListResponse: Decodable, Sendable {
    public let trips: [TripListItem]
    public let totalTrips: Int

    enum CodingKeys: String, CodingKey {
        case trips
        case totalTrips = "total_trips"
    }
}
