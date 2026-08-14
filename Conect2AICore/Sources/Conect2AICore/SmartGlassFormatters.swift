import Foundation

/// Behavior class labels returned by the MMCloud model, per language.
enum BehaviorLabel {
    static func text(_ label: String, _ language: AppLanguage) -> String {
        guard language == .ptBR else { return label.lowercased() }
        switch label.lowercased() {
        case "cautious": return "cautelosa"
        case "normal": return "normal"
        case "aggressive": return "agressiva"
        default: return label
        }
    }
}

/// Turns Smart Glass API responses into short sentences for the glasses'
/// speakers, in pt-BR or English. Deterministic (article reproducibility).
public struct SmartGlassFormatter: Sendable {
    private let language: AppLanguage

    public init(language: AppLanguage = .ptBR) {
        self.language = language
    }

    // MARK: - "como estou dirigindo?" / "how am I driving?"

    public func spokenDriverBehavior(_ response: DriverBehaviorResponse) -> String {
        let window = response.window
        guard window.sampleCount > 0, let predominant = window.predominantBehavior else {
            return language == .ptBR
                ? "Ainda não tenho dados suficientes da sua condução nos últimos \(minutesText(window.seconds))."
                : "I don't have enough driving data for the last \(minutesText(window.seconds)) yet."
        }
        var parts: [String] = []
        let label = BehaviorLabel.text(predominant, language)
        parts.append(language == .ptBR
            ? "Nos últimos \(minutesText(window.seconds)), sua condução foi predominantemente \(label)."
            : "In the last \(minutesText(window.seconds)), your driving was predominantly \(label).")

        let ordered = window.distribution.sorted { $0.value > $1.value }
        if ordered.count > 1 {
            let shares = ordered
                .filter { $0.value >= 1 }
                .map { "\(format($0.value, digits: 0))% \(BehaviorLabel.text($0.key, language))" }
            if !shares.isEmpty {
                parts.append(language == .ptBR
                    ? "Distribuição: \(shares.joined(separator: ", "))."
                    : "Breakdown: \(shares.joined(separator: ", ")).")
            }
        }
        return parts.joined(separator: " ")
    }

    // MARK: - "como estou emitindo?" / "how am I emitting?"

    /// Real-time emissions of the ongoing trip (GET /smart-glass/emissions/).
    public func spokenEmissions(_ realtime: SmartGlassEmissions) -> String {
        spokenEmissions(from: realtime.emissions)
    }

    public func spokenEmissions(_ summary: SmartGlassTripSummary) -> String {
        spokenEmissions(from: summary.emissions)
    }

    private func spokenEmissions(from emissions: SmartGlassTripSummary.Emissions?) -> String {
        guard let emissions,
              emissions.emissionByKm != nil || emissions.classification != nil else {
            return language == .ptBR
                ? "Ainda não tenho dados de emissão desta viagem."
                : "I don't have emission data for this trip yet."
        }
        var parts: [String] = []
        if let byKm = emissions.emissionByKm {
            parts.append(language == .ptBR
                ? "Você está emitindo \(format(byKm, digits: 0)) gramas de CO2 por quilômetro."
                : "You are emitting \(format(byKm, digits: 0)) grams of CO2 per kilometer.")
        }
        if let total = emissions.totalG, total > 0 {
            let kg = total / 1000
            if kg >= 1 {
                parts.append(language == .ptBR
                    ? "Total de \(format(kg, digits: 1)) quilos até agora."
                    : "\(format(kg, digits: 1)) kilograms in total so far.")
            } else {
                parts.append(language == .ptBR
                    ? "Total de \(format(total, digits: 0)) gramas até agora."
                    : "\(format(total, digits: 0)) grams in total so far.")
            }
        }
        if let classification = emissions.classification, !classification.isEmpty {
            parts.append(language == .ptBR
                ? "Sua classificação é \(classification)."
                : "Your rating is \(classification).")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Fallback: emissions from the LAST finished trip

    public func spokenEmissions(fromLastTrip trip: TripSummary) -> String {
        var parts: [String] = [language == .ptBR ? "Sem viagem ativa." : "No active trip."]
        if let byKm = trip.emissionByKm {
            parts.append(language == .ptBR
                ? "Na sua última viagem, você emitiu \(format(byKm, digits: 0)) gramas de CO2 por quilômetro."
                : "On your last trip, you emitted \(format(byKm, digits: 0)) grams of CO2 per kilometer.")
        }
        if let classification = trip.emissionClassification, !classification.isEmpty {
            parts.append(language == .ptBR
                ? "Classificação \(classification)."
                : "Rating \(classification).")
        }
        if parts.count == 1 {
            return language == .ptBR
                ? "Ainda não tenho dados de emissão."
                : "I don't have emission data yet."
        }
        return parts.joined(separator: " ")
    }

    // MARK: - "resumo da viagem" / "trip summary"

    public func spokenTripSummary(_ summary: SmartGlassTripSummary) -> String {
        var parts: [String] = []
        if let distance = summary.totalDistance, let seconds = summary.totalTimeSeconds {
            parts.append(language == .ptBR
                ? "Sua viagem percorreu \(format(distance, digits: 1)) quilômetros em \(durationText(seconds: seconds))."
                : "Your trip covered \(format(distance, digits: 1)) kilometers in \(durationText(seconds: seconds)).")
        }
        if let avg = summary.speed?.avg {
            var sentence = language == .ptBR
                ? "Velocidade média de \(format(avg, digits: 0)) quilômetros por hora"
                : "Average speed of \(format(avg, digits: 0)) kilometers per hour"
            if let max = summary.speed?.max {
                sentence += language == .ptBR
                    ? ", com máxima de \(format(max, digits: 0))"
                    : ", peaking at \(format(max, digits: 0))"
            }
            parts.append(sentence + ".")
        }
        if let fuel = summary.fuelPrediction, !fuel.isEmpty {
            parts.append(language == .ptBR
                ? "Combustível estimado: \(fuel)."
                : "Estimated fuel: \(fuel).")
        }
        if let emissions = summary.emissions {
            if let byKm = emissions.emissionByKm, let classification = emissions.classification {
                parts.append(language == .ptBR
                    ? "Emissão de \(format(byKm, digits: 0)) gramas por quilômetro, classificação \(classification)."
                    : "Emissions of \(format(byKm, digits: 0)) grams per kilometer, rating \(classification).")
            } else if let classification = emissions.classification {
                parts.append(language == .ptBR
                    ? "Classificação de emissão: \(classification)."
                    : "Emission rating: \(classification).")
            }
        }
        if let behavior = summary.driverBehavior, !behavior.isEmpty {
            let total = behavior.values.reduce(0, +)
            if total > 0, let top = behavior.max(by: { $0.value < $1.value }) {
                let pct = top.value / total * 100
                let label = BehaviorLabel.text(top.key, language)
                parts.append(language == .ptBR
                    ? "Condução \(format(pct, digits: 0))% do tempo \(label)."
                    : "Driving was \(label) \(format(pct, digits: 0))% of the time.")
            }
        }
        if parts.isEmpty {
            return language == .ptBR
                ? "Ainda não tenho dados suficientes desta viagem."
                : "I don't have enough data for this trip yet."
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Helpers

    private func minutesText(_ seconds: Int) -> String {
        if seconds < 60 {
            return language == .ptBR ? "\(seconds) segundos" : "\(seconds) seconds"
        }
        let minutes = seconds / 60
        if language == .ptBR {
            return minutes == 1 ? "um minuto" : "\(minutes) minutos"
        }
        return minutes == 1 ? "one minute" : "\(minutes) minutes"
    }

    func durationText(seconds: Double) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        if totalMinutes < 1 {
            return language == .ptBR ? "menos de um minuto" : "less than a minute"
        }
        if totalMinutes < 60 {
            if language == .ptBR {
                return totalMinutes == 1 ? "1 minuto" : "\(totalMinutes) minutos"
            }
            return totalMinutes == 1 ? "1 minute" : "\(totalMinutes) minutes"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let hourText: String
        if language == .ptBR {
            hourText = hours == 1 ? "1 hora" : "\(hours) horas"
            if minutes == 0 { return hourText }
            return "\(hourText) e \(minutes) minutos"
        }
        hourText = hours == 1 ? "1 hour" : "\(hours) hours"
        if minutes == 0 { return hourText }
        return "\(hourText) and \(minutes) minutes"
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
