import XCTest
import MWDATDisplay
import Conect2AICore
@testable import RayBanTripApp

/// The dashboard layout is pure data (FlexBox/Text structs), so its content is
/// verifiable without any device — mock or real.
final class GlassesDashboardTests: XCTestCase {

    private func makeTrip() throws -> TripSummary {
        let json = Data("""
        {
          "time_session": "2025-04-04T10:35:50",
          "location": [[null, null], [-5.84325, -35.1975275]],
          "total_distance": 114.64130849740646,
          "total_time": 2619.999597,
          "speed": {
            "series": [null, 50, 50],
            "statistics": {"avg": 34.157076205287716, "max": 95.0}
          },
          "fuel_prediction": "Gasolina",
          "emission_by_km": 35.565714081955385,
          "emission_classification": "A"
        }
        """.utf8)
        return try JSONDecoder().decode(TripSummary.self, from: json)
    }

    /// Recursively collects every Text content in the layout tree.
    private func allTexts(in component: any ViewComponent) -> [String] {
        if let text = component as? MWDATDisplay.Text { return [text.content] }
        if let box = component as? FlexBox {
            return box.children.flatMap { allTexts(in: $0) }
        }
        return []
    }

    func testDashboardShowsDistanceSpeedsFuelAndEmission() throws {
        let view = GlassesDashboard.makeView(for: try makeTrip())
        let texts = allTexts(in: view)

        XCTAssertTrue(texts.contains("114,6 km"), "distance line missing: \(texts)")
        XCTAssertTrue(texts.contains("44 min"), "duration line missing: \(texts)")
        XCTAssertTrue(texts.contains("méd 34 km/h"), "avg speed line missing: \(texts)")
        XCTAssertTrue(texts.contains("máx 95 km/h"), "max speed line missing: \(texts)")
        XCTAssertTrue(texts.contains("Gasolina"), "fuel line missing: \(texts)")
        XCTAssertTrue(texts.contains("Emissão A"), "emission line missing: \(texts)")
    }

    func testDashboardHandlesMissingOptionalFieldsWithPlaceholders() throws {
        let json = Data("""
        {
          "time_session": "2025-04-04T10:35:50",
          "total_distance": 10.0,
          "total_time": 65.0,
          "speed": {"series": [], "statistics": {}}
        }
        """.utf8)
        let trip = try JSONDecoder().decode(TripSummary.self, from: json)
        let texts = allTexts(in: GlassesDashboard.makeView(for: trip))

        XCTAssertTrue(texts.contains("méd —"))
        XCTAssertTrue(texts.contains("máx —"))
        XCTAssertTrue(texts.contains("—"), "fuel placeholder missing")
        XCTAssertTrue(texts.contains("Emissão —"))
    }
}
