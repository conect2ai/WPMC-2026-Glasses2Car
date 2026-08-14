import Foundation
import AVFoundation
import Speech
import Conect2AICore

/// A recognized voice interaction, with the timestamps the metrics need.
struct VoiceIntentEvent {
    let intent: VoiceIntent
    let transcript: String
    let wakeAt: Date
    let commandAt: Date
}

/// Thread-safe holder so the audio tap (real-time thread) can feed whichever
/// recognition request is currently active, without restarting the engine.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var peak: Float = 0

    func set(_ newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); request = newRequest; lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        request?.append(buffer)
        if let data = buffer.floatChannelData?[0] {
            let n = Int(buffer.frameLength)
            var p: Float = 0
            for i in stride(from: 0, to: n, by: 16) { p = max(p, abs(data[i])) }
            peak = max(peak, p)
        }
        lock.unlock()
    }

    /// Highest mic sample since the last call — tells a live mic from a dead one.
    func readAndResetPeak() -> Float {
        lock.lock(); defer { lock.unlock() }
        let value = peak; peak = 0
        return value
    }
}

/// Hands-free voice pipeline using the glasses' microphone (Bluetooth HFP):
///
/// 1. **Wake stage** — continuously listens for "ei Conecta";
/// 2. On wake, answers "Sim?" and enters the **command stage** (~10 s window);
/// 3. A recognized command ("resumo/viagem/última...") fires `onCommand`.
///
/// The audio engine runs continuously — only the recognition request is
/// recycled between stages. Restarting capture while TTS renegotiates the
/// HFP route yields a silently dead microphone (observed on hardware), so
/// route changes are handled via AVAudioEngineConfigurationChange instead.
@MainActor
final class VoiceCommandListener: ObservableObject {
    enum Stage { case wake, command }

    @Published private(set) var isListening = false
    @Published private(set) var status: String?

    /// Called when a command is recognized after the wake word.
    var onIntent: ((VoiceIntentEvent) -> Void)?

    // Matching happens on lowercased, diacritic-folded text. Loose on purpose:
    // HFP audio is 8 kHz mono and the recognizer gets creative with it.
    // "conect" covers pt-BR hearings; "connect" (double n) covers what the
    // en-US recognizer makes of "Conecta": connected/connector/connecting.
    private let wakeTokens = ["conect", "connect", "kinect"]
    private var lastPrinted = ""
    private var wakeHeardAt = Date()
    /// Transcript length at the moment the wake word matched; command tokens
    /// are only searched in text produced after this point.
    private var wakeOffset = 0

    private var stage: Stage = .wake
    private var language: AppLanguage = .ptBR
    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private let box = RequestBox()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var commandDeadline: Task<Void, Never>?
    /// Bumped on every recognition restart; results from older tasks are
    /// dropped (cancelled SFSpeech tasks still deliver trailing partials,
    /// which otherwise re-trigger the wake word with stale text).
    private var generation = 0
    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private let feedback: AVSpeechSynthesizer = {
        let synth = AVSpeechSynthesizer()
        // Critical: by default the synthesizer runs its own audio session,
        // interrupting (and silently killing) our capture session every time
        // it speaks. Sharing the app session keeps the mic alive during TTS.
        synth.usesApplicationAudioSession = true
        return synth
    }()

    func toggle() {
        if isListening { stop() } else { start() }
    }

    func start() {
        guard !isListening else { return }
        Task { [weak self] in await self?.startAsync() }
    }

    private func startAsync() async {
        language = LanguageSetting.current
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))
        guard let recognizer, recognizer.isAvailable else {
            status = language == .ptBR
                ? "Reconhecimento de fala indisponível neste aparelho."
                : "Speech recognition unavailable on this device."
            return
        }

        let micGranted = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micGranted else {
            status = language == .ptBR
                ? "Permissão de microfone negada (Ajustes → RayBanTripApp)."
                : "Microphone permission denied (Settings → RayBanTripApp)."
            return
        }

        let speechAuth = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechAuth == .authorized else {
            status = language == .ptBR
                ? "Permissão de reconhecimento de fala negada."
                : "Speech recognition permission denied."
            return
        }

        do {
            try configureAudioSession()
            try startEngine()
            observeRouteChanges()
            isListening = true
            enterWakeStage(announceRoute: true)
        } catch {
            status = "Falha ao iniciar escuta: \(error.localizedDescription)"
            stop()
        }
    }

    /// HFP is required for glasses microphone capture (A2DP is output-only).
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        if let hfp = session.availableInputs?.first(where: { $0.portType == .bluetoothHFP }) {
            try session.setPreferredInput(hfp)
            print("VOICE using HFP input:", hfp.portName)
        } else {
            print("VOICE no HFP input available, using default mic")
        }
    }

    /// Starts (or re-arms) the continuous capture engine feeding the box.
    private func startEngine() throws {
        let input = audioEngine.inputNode
        let format = input.inputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [box] buffer, _ in
            box.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        print("VOICE engine running, input format:", format)
    }

    /// TTS playback renegotiates the HFP route and can invalidate the input
    /// node; re-arm capture whenever the engine configuration changes.
    private func observeRouteChanges() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                print("VOICE engine configuration changed — re-arming capture")
                try? self.startEngine()
                self.restartRecognition(afterSeconds: 0.2)
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init)
            Task { @MainActor in
                guard let self, self.isListening else { return }
                print("VOICE session interruption:", type == .began ? "began" : "ended")
                if type == .ended {
                    try? self.configureAudioSession()
                    try? self.startEngine()
                    self.restartRecognition(afterSeconds: 0.2)
                }
            }
        }
    }

    // MARK: - Stages

    private func enterWakeStage(announceRoute: Bool = false) {
        stage = .wake
        commandDeadline?.cancel()
        let wakePhrase = language == .ptBR ? "ei Conecta" : "hey Conecta"
        if announceRoute {
            let route = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName
                ?? (language == .ptBR ? "microfone" : "microphone")
            status = language == .ptBR
                ? "Ouvindo pelo \(route) — diga \"\(wakePhrase)\""
                : "Listening via \(route) — say \"\(wakePhrase)\""
        } else {
            status = language == .ptBR ? "Diga \"\(wakePhrase)\"" : "Say \"\(wakePhrase)\""
        }
        restartRecognition(afterSeconds: 0.2)
    }

    /// Keeps the SAME recognition task across the stage switch — creating a
    /// fresh task while TTS is playing proved to fail silently on hardware.
    /// Command detection just looks at transcript text past `wakeOffset`.
    private func enterCommandStage() {
        stage = .command
        status = language == .ptBR ? "Sim? (aguardando comando…)" : "Yes? (waiting for command…)"
        _ = box.readAndResetPeak()
        speak(language == .ptBR ? "Sim?" : "Yes?")

        commandDeadline?.cancel()
        commandDeadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, let self, self.isListening, self.stage == .command else { return }
            print("VOICE command window timed out — mic peak during window: \(self.box.readAndResetPeak())")
            self.speak(self.language == .ptBR ? "Não entendi." : "Sorry, I didn't catch that.")
            self.enterWakeStage()
        }
    }

    private func fire(_ intent: VoiceIntent, transcript: String) {
        print("VOICE intent fired:", intent.rawValue)
        status = language == .ptBR ? "Comando reconhecido — consultando…" : "Command recognized — fetching…"
        commandDeadline?.cancel()
        onIntent?(VoiceIntentEvent(intent: intent, transcript: transcript,
                                   wakeAt: wakeHeardAt, commandAt: Date()))
        // Give the spoken answer a head start before matching again.
        stage = .wake
        restartRecognition(afterSeconds: 4)
    }

    // MARK: - Recognition loop (engine keeps running; only requests recycle)

    private func startRecognition() throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = language == .ptBR
            ? ["Conecta", "ei Conecta", "resumo da viagem", "emitindo", "dirigindo"]
            : ["Conecta", "hey Conecta", "trip summary", "emitting", "driving"]
        self.request = request
        box.set(request)

        if !audioEngine.isRunning {
            print("VOICE engine was stopped — re-arming before recognition")
            try startEngine()
        }

        generation += 1
        let gen = generation
        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isListening, self.generation == gen else { return }
                if let result {
                    self.handleTranscript(result.bestTranscription.formattedString)
                }
                // Recognition tasks expire (~1 min of audio); keep the loop alive.
                if error != nil || (result?.isFinal ?? false) {
                    self.restartRecognition(afterSeconds: 0.8)
                }
            }
        }
    }

    private func handleTranscript(_ raw: String) {
        let text = normalize(raw)
        if text != lastPrinted {
            lastPrinted = text
            print("VOICE heard [\(stage)]:", text)
        }
        switch stage {
        case .wake:
            guard let token = wakeTokens.first(where: { text.contains($0) }) else {
                // Live feedback so the user sees what the recognizer got.
                if !text.isEmpty {
                    status = language == .ptBR
                        ? "Ouvindo… (ouvi: \"\(String(raw.suffix(40)))\")"
                        : "Listening… (heard: \"\(String(raw.suffix(40)))\")"
                }
                return
            }
            print("VOICE wake word heard:", raw)
            wakeHeardAt = Date()
            // "ei conecta resumo da viagem" in one breath: fast path.
            if let range = text.range(of: token),
               let intent = VoiceIntent.parse(String(text[range.upperBound...])) {
                fire(intent, transcript: raw)
            } else {
                wakeOffset = text.count
                enterCommandStage()
            }
        case .command:
            let tail = String(text.dropFirst(min(wakeOffset, text.count)))
            guard let intent = VoiceIntent.parse(tail) else { return }
            print("VOICE command heard:", raw)
            fire(intent, transcript: raw)
        }
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.rawValue)
        feedback.speak(utterance)
    }

    private func restartRecognition(afterSeconds delay: Double) {
        generation += 1   // drop trailing partials from the task being replaced
        task?.cancel(); task = nil
        box.set(nil)
        request?.endAudio(); request = nil
        lastPrinted = ""
        wakeOffset = 0
        guard isListening else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.isListening else { return }
            do {
                try self.startRecognition()
            } catch {
                self.status = (self.language == .ptBR ? "Escuta interrompida: " : "Listening stopped: ")
                    + error.localizedDescription
                self.isListening = false
            }
        }
    }

    func stop() {
        isListening = false
        commandDeadline?.cancel(); commandDeadline = nil
        task?.cancel(); task = nil
        box.set(nil)
        request?.endAudio(); request = nil
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        routeObserver = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        status = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
