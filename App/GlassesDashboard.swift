import Foundation
import MWDATDisplay
import Conect2AICore

/// Builds the driver dashboard layout rendered on Meta Ray-Ban Display glasses
/// (600x600 lens display). Kept glanceable on purpose: a driver should absorb
/// it in under a second — large distance figure, one speed row, one status row.
enum GlassesDashboard {

    /// Root view for `Display.send(_:)`.
    static func makeView(for trip: TripSummary) -> FlexBox {
        FlexBox(direction: .column, spacing: 16, alignment: .center, crossAlignment: .center) {
            Text("CONECT2AI · ÚLTIMA VIAGEM", style: .meta, color: .secondary)
            Text(distanceText(for: trip), style: .heading)
            Text(durationText(for: trip), style: .body, color: .secondary)
            FlexBox(direction: .row, spacing: 24, alignment: .center) {
                Text(averageSpeedText(for: trip), style: .body)
                Text(maxSpeedText(for: trip), style: .body)
            }
            FlexBox(direction: .row, spacing: 24, alignment: .center) {
                Text(fuelText(for: trip), style: .body, color: .secondary)
                Text(emissionText(for: trip), style: .body)
            }
        }
        .padding(24)
        .background(.card)
    }

    // MARK: - Line builders (short, glanceable strings)

    static func distanceText(for trip: TripSummary) -> String {
        "\(format(trip.totalDistance, digits: 1)) km"
    }

    static func durationText(for trip: TripSummary) -> String {
        let minutes = Int((trip.totalTime / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h\(String(format: "%02d", minutes % 60))"
    }

    static func averageSpeedText(for trip: TripSummary) -> String {
        guard let avg = trip.speed.statistics.avg else { return "méd —" }
        return "méd \(format(avg, digits: 0)) km/h"
    }

    static func maxSpeedText(for trip: TripSummary) -> String {
        guard let max = trip.speed.statistics.max else { return "máx —" }
        return "máx \(format(max, digits: 0)) km/h"
    }

    static func fuelText(for trip: TripSummary) -> String {
        trip.fuelPrediction ?? "—"
    }

    static func emissionText(for trip: TripSummary) -> String {
        guard let classification = trip.emissionClassification else { return "Emissão —" }
        return "Emissão \(classification)"
    }

    private static func format(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
