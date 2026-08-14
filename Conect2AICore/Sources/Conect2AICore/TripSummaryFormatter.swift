import Foundation

/// Turns a ``TripSummary`` (last finished trip) into a short sentence,
/// in pt-BR or English.
public struct TripSummaryFormatter: Sendable {
    private let language: AppLanguage

    public init(language: AppLanguage = .ptBR) {
        self.language = language
    }

    public func spokenSummary(for trip: TripSummary) -> String {
        var parts: [String] = []
        parts.append(language == .ptBR
            ? "Sua última viagem percorreu \(format(trip.totalDistance, digits: 1)) quilômetros em \(duration(seconds: trip.totalTime))."
            : "Your last trip covered \(format(trip.totalDistance, digits: 1)) kilometers in \(duration(seconds: trip.totalTime)).")

        if let avg = trip.speed.statistics.avg {
            var speedSentence = language == .ptBR
                ? "Velocidade média de \(format(avg, digits: 0)) quilômetros por hora"
                : "Average speed of \(format(avg, digits: 0)) kilometers per hour"
            if let max = trip.speed.statistics.max {
                speedSentence += language == .ptBR
                    ? ", com máxima de \(format(max, digits: 0))"
                    : ", peaking at \(format(max, digits: 0))"
            }
            parts.append(speedSentence + ".")
        }

        if let fuel = trip.fuelPrediction, !fuel.isEmpty {
            parts.append(language == .ptBR
                ? "Combustível estimado: \(fuel)."
                : "Estimated fuel: \(fuel).")
        }

        if let classification = trip.emissionClassification, !classification.isEmpty {
            parts.append(language == .ptBR
                ? "Classificação de emissão: \(classification)."
                : "Emission rating: \(classification).")
        }

        return parts.joined(separator: " ")
    }

    func duration(seconds: Double) -> String {
        SmartGlassFormatter(language: language).durationText(seconds: seconds)
    }

    private func format(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
