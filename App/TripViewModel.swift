import Foundation
import AVFoundation
import CoreLocation
import Conect2AICore

/// Executes voice intents against the Smart Glass API, speaks the answer and
/// records one metrics row per interaction (see MetricsRecorder).
@MainActor
final class TripViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var username = ""
    @Published var password = ""
    @Published private(set) var isLoggedIn = false
    @Published private(set) var answerText: String?
    @Published private(set) var errorMessage: String?

    let location = LocationProvider()
    let metrics = MetricsRecorder()

    private let client: Conect2APIClient
    private var language: AppLanguage { LanguageSetting.current }
    private var formatter: SmartGlassFormatter { SmartGlassFormatter(language: language) }
    private let synthesizer: AVSpeechSynthesizer = {
        let synth = AVSpeechSynthesizer()
        // Share the app audio session so speaking doesn't kill the voice
        // listener's microphone capture (see VoiceCommandListener).
        synth.usesApplicationAudioSession = true
        return synth
    }()

    private var interactionCounter = 0
    /// Metrics of the interaction whose TTS is currently in flight.
    private var pendingRow: MetricRow?
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    override init() {
        self.client = Conect2APIClient(baseURL: AppConfig.apiBaseURL)
        super.init()
        synthesizer.delegate = self
        #if DEBUG
        // UI review without credentials (simulator screenshots).
        if ProcessInfo.processInfo.arguments.contains("--ui-preview") {
            isLoggedIn = true
            answerText = "Nos últimos 2 minutos, sua condução foi predominantemente normal. Distribuição: 72% normal, 18% cautelosa, 10% agressiva."
        }
        #endif
    }

    func login() async {
        errorMessage = nil
        do {
            try await client.login(username: username, password: password)
            isLoggedIn = true
            location.start()
        } catch {
            errorMessage = L10n(language).loginError
        }
    }

    // MARK: - Intent pipeline (instrumented for the article metrics)

    func handle(_ event: VoiceIntentEvent, trigger: String = "voice") async {
        errorMessage = nil
        interactionCounter += 1

        var row = MetricRow(id: interactionCounter, trigger: trigger, event: event)
        row.cpuPct = SystemStats.cpuPercent()
        row.memMB = SystemStats.memoryFootprintMB()
        row.thermal = SystemStats.thermalState()
        row.batteryPct = SystemStats.batteryPercent()
        row.glassesThermal = WearablesManager.latestGlassesThermal

        let sentLocation = location.current
        row.latSent = sentLocation?.coordinate.latitude
        row.lonSent = sentLocation?.coordinate.longitude
        row.tRequestSent = Date()

        var spokenText: String
        do {
            let apiStart = Date()
            switch event.intent {
            case .drivingBehavior:
                let response = try await client.smartGlassDriverBehavior(
                    latitude: sentLocation?.coordinate.latitude,
                    longitude: sentLocation?.coordinate.longitude,
                    windowSeconds: AppConfig.behaviorWindowSeconds)
                row.endpoint = "smart-glass/driver-behavior"
                row.tResponseReceived = Date()
                row.apiMs = row.tResponseReceived!.timeIntervalSince(apiStart) * 1000
                row.rawResponse = response.rawString
                row.reqBytesEst = response.requestBytesEstimate
                row.respBodyBytes = response.responseBodyBytes
                row.windowStart = response.value.window.windowStart
                row.windowEnd = response.value.window.windowEnd
                row.lastSampleAt = response.value.lastSampleAt
                let formatStart = Date()
                spokenText = formatter.spokenDriverBehavior(response.value)
                row.formatMs = Date().timeIntervalSince(formatStart) * 1000
            case .emissions:
                do {
                    let realtime = try await client.smartGlassEmissions(
                        latitude: sentLocation?.coordinate.latitude,
                        longitude: sentLocation?.coordinate.longitude)
                    row.endpoint = "smart-glass/emissions"
                    row.tResponseReceived = Date()
                    row.apiMs = row.tResponseReceived!.timeIntervalSince(apiStart) * 1000
                    row.rawResponse = realtime.rawString
                    row.reqBytesEst = realtime.requestBytesEstimate
                    row.respBodyBytes = realtime.responseBodyBytes
                    row.lastSampleAt = realtime.value.lastSampleAt
                    let formatStart = Date()
                    spokenText = formatter.spokenEmissions(realtime.value)
                    row.formatMs = Date().timeIntervalSince(formatStart) * 1000
                } catch Conect2APIClient.APIError.notFound {
                    // No active trip on the smart-glass side: last finished trip.
                    let trip = try await client.lastTripSummaryRaw()
                    row.endpoint = "user-area/last-trip-summary (fallback)"
                    row.tResponseReceived = Date()
                    row.apiMs = row.tResponseReceived!.timeIntervalSince(apiStart) * 1000
                    row.rawResponse = trip.rawString
                    row.reqBytesEst = trip.requestBytesEstimate
                    row.respBodyBytes = trip.responseBodyBytes
                    let formatStart = Date()
                    spokenText = formatter.spokenEmissions(fromLastTrip: trip.value)
                    row.formatMs = Date().timeIntervalSince(formatStart) * 1000
                }
            case .tripSummary:
                do {
                    let summary = try await client.smartGlassTripSummary(
                        latitude: sentLocation?.coordinate.latitude,
                        longitude: sentLocation?.coordinate.longitude,
                        sendEmail: false)
                    row.endpoint = "smart-glass/trip/summary"
                    row.tResponseReceived = Date()
                    row.apiMs = row.tResponseReceived!.timeIntervalSince(apiStart) * 1000
                    row.rawResponse = summary.rawString
                    row.reqBytesEst = summary.requestBytesEstimate
                    row.respBodyBytes = summary.responseBodyBytes
                    let formatStart = Date()
                    spokenText = formatter.spokenTripSummary(summary.value)
                    row.formatMs = Date().timeIntervalSince(formatStart) * 1000
                } catch Conect2APIClient.APIError.notFound {
                    // No active trip on the smart-glass side: last finished trip.
                    let trip = try await client.lastTripSummaryRaw()
                    row.endpoint = "user-area/last-trip-summary (fallback)"
                    row.tResponseReceived = Date()
                    row.apiMs = row.tResponseReceived!.timeIntervalSince(apiStart) * 1000
                    row.rawResponse = trip.rawString
                    row.reqBytesEst = trip.requestBytesEstimate
                    row.respBodyBytes = trip.responseBodyBytes
                    let formatStart = Date()
                    spokenText = TripSummaryFormatter(language: language).spokenSummary(for: trip.value)
                    row.formatMs = Date().timeIntervalSince(formatStart) * 1000
                }
            }
        } catch Conect2APIClient.APIError.notFound {
            row.apiError = "404"
            spokenText = L10n(language).noTripData
        } catch {
            row.apiError = String(describing: error)
            spokenText = L10n(language).queryFailed
        }
        if row.tResponseReceived == nil { row.tResponseReceived = Date() }
        let receivedLocation = location.current
        row.latRecv = receivedLocation?.coordinate.latitude
        row.lonRecv = receivedLocation?.coordinate.longitude

        answerText = spokenText
        row.spokenChars = spokenText.count
        row.spokenText = spokenText
        speak(spokenText, recording: row)
    }

    // MARK: - TTS with timing

    private func speak(_ text: String, recording row: MetricRow) {
        // If a previous interaction's TTS never completed, flush it first.
        if let previous = pendingRow { metrics.append(previous.fields(iso: Self.iso)) }
        var row = row
        row.tTTSRequested = Date()
        pendingRow = row
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.rawValue)
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard var row = pendingRow, let requested = row.tTTSRequested else { return }
            row.ttsSynthesisDelayMs = Date().timeIntervalSince(requested) * 1000
            pendingRow = row
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard var row = pendingRow else { return }
            if let requested = row.tTTSRequested, let delay = row.ttsSynthesisDelayMs {
                row.ttsDurationMs = Date().timeIntervalSince(requested) * 1000 - delay
            }
            row.totalMs = Date().timeIntervalSince(row.wakeAt) * 1000
            metrics.append(row.fields(iso: Self.iso))
            pendingRow = nil
        }
    }
}

/// One metrics CSV row in the making; column order must match MetricsRecorder.header.
struct MetricRow {
    let id: Int
    let trigger: String
    let intent: String
    var endpoint: String?
    let transcript: String
    let wakeAt: Date
    let commandAt: Date

    var tRequestSent: Date?
    var latSent: Double?
    var lonSent: Double?
    var tResponseReceived: Date?
    var latRecv: Double?
    var lonRecv: Double?
    var apiMs: Double?
    var apiError: String?
    var reqBytesEst: Int?
    var respBodyBytes: Int?
    var formatMs: Double?
    var tTTSRequested: Date?
    var ttsSynthesisDelayMs: Double?
    var ttsDurationMs: Double?
    var spokenChars: Int?
    var totalMs: Double?
    var cpuPct: Double?
    var memMB: Double?
    var thermal: String?
    var batteryPct: Double?
    var glassesThermal: String?
    var windowStart: String?
    var windowEnd: String?
    var lastSampleAt: String?
    var spokenText: String?
    var rawResponse: String?

    init(id: Int, trigger: String, event: VoiceIntentEvent) {
        self.id = id
        self.trigger = trigger
        self.intent = event.intent.rawValue
        self.transcript = event.transcript
        self.wakeAt = event.wakeAt
        self.commandAt = event.commandAt
    }

    func fields(iso: ISO8601DateFormatter) -> [String] {
        func ms(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "" }
        func num(_ value: Double?) -> String { value.map { String($0) } ?? "" }
        func date(_ value: Date?) -> String { value.map(iso.string(from:)) ?? "" }
        return [
            String(id), trigger, intent, endpoint ?? "", transcript,
            iso.string(from: wakeAt), iso.string(from: commandAt),
            ms(commandAt.timeIntervalSince(wakeAt) * 1000),
            date(tRequestSent), num(latSent), num(lonSent),
            date(tResponseReceived), num(latRecv), num(lonRecv),
            ms(apiMs), apiError ?? "",
            reqBytesEst.map(String.init) ?? "", respBodyBytes.map(String.init) ?? "",
            ms(formatMs),
            date(tTTSRequested), ms(ttsSynthesisDelayMs), ms(ttsDurationMs),
            spokenChars.map(String.init) ?? "",
            ms(totalMs),
            ms(cpuPct), ms(memMB), thermal ?? "", ms(batteryPct), glassesThermal ?? "",
            windowStart ?? "", windowEnd ?? "", lastSampleAt ?? "",
            spokenText ?? "", rawResponse ?? "",
        ]
    }
}
