import Foundation

/// The commands the glasses understand. Parsing is deliberately loose —
/// input text comes from 8 kHz HFP audio through speech recognition.
public enum VoiceIntent: String, CaseIterable, Sendable {
    case drivingBehavior = "driving_behavior"
    case emissions = "emissions"
    case tripSummary = "trip_summary"

    /// Parses a normalized (lowercased, diacritic-folded) transcript.
    /// Portuguese and English tokens are always both accepted — no need to
    /// switch token sets when the user flips the app language.
    /// Specific intents win over the generic trip summary.
    public static func parse(_ normalizedText: String) -> VoiceIntent? {
        if ["dirigindo", "direcao", "conducao", "comportamento",
            "driving", "drive", "behavior"].contains(where: normalizedText.contains) {
            return .drivingBehavior
        }
        // "meeting"/"mission" are what the en-US recognizer tends to make of
        // "emitting"/"emission" (observed on hardware over 8 kHz HFP audio);
        // safe to accept because command parsing only runs post-wake.
        if ["emitindo", "emissao", "emissoes", "emissa", "poluindo", "co2",
            "emitting", "emission", "polluting", "carbon", "meeting", "mission"].contains(where: normalizedText.contains) {
            return .emissions
        }
        if ["resumo", "viagem", "ultima",
            "summary", "trip", "last"].contains(where: normalizedText.contains) {
            return .tripSummary
        }
        return nil
    }
}
