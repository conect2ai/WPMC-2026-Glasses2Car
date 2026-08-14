import Foundation

/// Output language for generated text, TTS voice and speech recognition.
public enum AppLanguage: String, CaseIterable, Sendable {
    case ptBR = "pt-BR"
    case enUS = "en-US"

    /// Locale for number formatting (decimal comma vs. point).
    public var locale: Locale {
        Locale(identifier: self == .ptBR ? "pt_BR" : "en_US")
    }
}
