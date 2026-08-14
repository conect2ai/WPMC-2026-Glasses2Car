import Foundation
import Conect2AICore

/// Current app language, persisted in UserDefaults and read app-wide.
enum LanguageSetting {
    static let key = "appLanguage"

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "pt-BR") ?? .ptBR
    }
}

/// UI strings for the two supported languages. Kept in code (small app,
/// two languages) so the language switch is instant and self-contained.
struct L10n {
    let lang: AppLanguage

    init(_ lang: AppLanguage) { self.lang = lang }

    private func t(_ pt: String, _ en: String) -> String { lang == .ptBR ? pt : en }

    // Login
    var appTitle: String { "Conect2AI Glasses" }
    var tagline: String { t("Pergunte aos seus óculos como você está dirigindo, emitindo e viajando.",
                            "Ask your glasses how you are driving, emitting and traveling.") }
    var username: String { t("Usuário", "Username") }
    var password: String { t("Senha", "Password") }
    var login: String { "Login" }
    var apiFootnote: String { t("API de testes · Conecta.ai / UFRN", "Test API · Conecta.ai / UFRN") }
    var loginError: String { t("Falha no login. Verifique usuário e senha.",
                               "Login failed. Check your username and password.") }

    // Status tiles
    var glasses: String { t("Óculos", "Glasses") }
    var listeningTile: String { t("Escuta \"ei Conecta\"", "\"Hey Conecta\" listening") }
    var listeningOn: String { t("Ativa", "On") }
    var listeningOff: String { t("Desligada", "Off") }
    var stateReady: String { t("Pronto", "Ready") }
    var stateConnecting: String { t("Conectando…", "Connecting…") }
    var stateStreaming: String { t("Transmitindo", "Streaming") }
    var statePaused: String { t("Pausado", "Paused") }
    var stateStopped: String { t("Parado", "Stopped") }

    // Smart Glass menu
    var askTitle: String { t("Pergunte aos óculos", "Ask your glasses") }
    var qDriving: String { t("Como estou dirigindo?", "How am I driving?") }
    var qDrivingSub: String { t("Comportamento nos últimos 2 minutos", "Behavior in the last 2 minutes") }
    var qEmissions: String { t("Como estou emitindo?", "How am I emitting?") }
    var qEmissionsSub: String { t("CO₂ por km e classificação", "CO₂ per km and rating") }
    var qSummary: String { t("Resumo da viagem", "Trip summary") }
    var qSummarySub: String { t("Distância, tempo, velocidade e emissões", "Distance, time, speed and emissions") }

    // Voice
    var voiceCommands: String { t("Comandos de voz", "Voice commands") }

    // Glasses card
    var glassesCard: String { t("Óculos Ray-Ban Meta", "Ray-Ban Meta glasses") }
    var registerMetaAI: String { t("Registrar no Meta AI", "Register with Meta AI") }
    var connectStream: String { t("Conectar e transmitir", "Connect and stream") }
    var capturePhoto: String { t("Capturar foto", "Capture photo") }
    var capturePhotoSub: String { t("Dispara o resumo da viagem", "Triggers the trip summary") }

    // Metrics
    var metricsTitle: String { t("Métricas do estudo", "Study metrics") }
    var interactions: String { t("Interações registradas", "Recorded interactions") }
    var exportCSV: String { t("Exportar CSV", "Export CSV") }
    var clear: String { t("Limpar", "Clear") }

    // Pipeline messages
    var noTripData: String { t("Ainda não há dados desta viagem.", "There is no data for this trip yet.") }
    var queryFailed: String { t("Não consegui consultar os dados agora.", "I couldn't fetch the data right now.") }
}
