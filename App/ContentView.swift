import SwiftUI
import Conect2AICore

struct ContentView: View {
    @StateObject private var wearables = WearablesManager()
    @StateObject private var viewModel = TripViewModel()
    @StateObject private var voice = VoiceCommandListener()
    @AppStorage(LanguageSetting.key) private var languageRaw = "pt-BR"

    private var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .ptBR }
    private var s: L10n { L10n(lang) }

    var body: some View {
        ZStack {
            Color.c2aBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    C2ALogo()
                        .padding(.top, 8)

                    languageToggle

                    if !viewModel.isLoggedIn {
                        loginCard
                    } else {
                        statusTiles
                        smartGlassCard
                        if let answer = viewModel.answerText {
                            answerCard(answer)
                        }
                        voiceCard
                        glassesCard
                        MetricsCard(metrics: viewModel.metrics, s: s)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color.c2aDanger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            wearables.observeRegistration()
            // Photo captured on the glasses acts as a trip-summary trigger.
            wearables.onPhotoCaptured = { _ in
                Task { @MainActor in
                    let now = Date()
                    await viewModel.handle(
                        VoiceIntentEvent(intent: .tripSummary, transcript: "captura de foto",
                                         wakeAt: now, commandAt: now),
                        trigger: "photo")
                }
            }
            voice.onIntent = { event in
                Task { await viewModel.handle(event) }
            }
        }
        .onChange(of: viewModel.isLoggedIn) { loggedIn in
            // Hands-free by default: listening starts right after login.
            if loggedIn { voice.start() }
        }
        .onChange(of: languageRaw) { _ in
            // Recognizer locale and prompts follow the language: restart.
            if voice.isListening {
                voice.stop()
                voice.start()
            }
        }
        .onOpenURL { url in
            // Meta AI calls back via conect2aiglasses:// after registration.
            wearables.handleCallback(url: url)
        }
    }

    // MARK: - Language

    /// App2Car-style EN ⇄ PT-BR switch under the logo.
    private var languageToggle: some View {
        HStack(spacing: 10) {
            Text("EN")
                .foregroundStyle(lang == .enUS ? .white : Color.c2aTextSecondary)
            Toggle("", isOn: Binding(
                get: { lang == .ptBR },
                set: { languageRaw = ($0 ? AppLanguage.ptBR : .enUS).rawValue }))
                .labelsHidden()
                .tint(Color.c2aAccent)
            Text("PT-BR")
                .foregroundStyle(lang == .ptBR ? .white : Color.c2aTextSecondary)
        }
        .font(.system(.footnote, design: .rounded).weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Login

    private var loginCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "eyeglasses")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.c2aAccent)
                .padding(.top, 22)
            Text(s.appTitle)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text(s.tagline)
                .font(.subheadline)
                .foregroundStyle(Color.c2aTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            TextField("", text: $viewModel.username,
                      prompt: Text(s.username).foregroundColor(.c2aTextSecondary))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .modifier(C2AFieldStyle())
            SecureField("", text: $viewModel.password,
                        prompt: Text(s.password).foregroundColor(.c2aTextSecondary))
                .modifier(C2AFieldStyle())

            Button(s.login) {
                Task { await viewModel.login() }
            }
            .buttonStyle(C2APrimaryButtonStyle())
            .padding(.top, 4)

            Text(s.apiFootnote)
                .font(.caption2)
                .foregroundStyle(Color.c2aTextSecondary.opacity(0.7))
                .padding(.bottom, 6)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.c2aCardDeep))
        .padding(.top, 28)
    }

    // MARK: - Logged-in sections

    private var statusTiles: some View {
        HStack(spacing: 12) {
            C2AMetricTile(caption: s.glasses,
                          value: glassesStateLabel,
                          icon: "eyeglasses")
            C2AMetricTile(caption: s.listeningTile,
                          value: voice.isListening ? s.listeningOn : s.listeningOff,
                          icon: voice.isListening ? "waveform" : "mic.slash.fill")
        }
    }

    private var glassesStateLabel: String {
        switch wearables.state {
        case .idle: return s.stateReady
        case .starting: return s.stateConnecting
        case .streaming: return s.stateStreaming
        case .paused: return s.statePaused
        case .stopped: return s.stateStopped
        }
    }

    private var smartGlassCard: some View {
        C2ACard {
            Text(s.askTitle)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
            C2AMenuRow(icon: "steeringwheel", title: s.qDriving, subtitle: s.qDrivingSub) {
                trigger(.drivingBehavior)
            }
            Divider().overlay(Color.white.opacity(0.08))
            C2AMenuRow(icon: "leaf.fill", title: s.qEmissions, subtitle: s.qEmissionsSub) {
                trigger(.emissions)
            }
            Divider().overlay(Color.white.opacity(0.08))
            C2AMenuRow(icon: "map.fill", title: s.qSummary, subtitle: s.qSummarySub) {
                trigger(.tripSummary)
            }
        }
    }

    private func answerCard(_ answer: String) -> some View {
        C2ACard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.c2aAccent)
                Text(answer)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    private var voiceCard: some View {
        C2ACard {
            HStack(spacing: 14) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(voice.isListening ? Color.c2aAccent : Color.c2aTextSecondary)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.c2aCardDeep))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.voiceCommands)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(.white)
                    if let voiceStatus = voice.status {
                        Text(voiceStatus)
                            .font(.footnote)
                            .foregroundStyle(Color.c2aTextSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { voice.isListening },
                    set: { _ in voice.toggle() }))
                    .labelsHidden()
                    .tint(Color.c2aAccent)
            }
        }
    }

    private var glassesCard: some View {
        C2ACard {
            Text(s.glassesCard)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
            C2AMenuRow(icon: "person.crop.circle.badge.checkmark", title: s.registerMetaAI,
                       subtitle: wearables.registrationStatus) {
                wearables.startGlassesRegistration()
            }
            Divider().overlay(Color.white.opacity(0.08))
            C2AMenuRow(icon: "dot.radiowaves.left.and.right", title: s.connectStream,
                       subtitle: wearables.connectionStatus) {
                wearables.connectAndStream()
            }
            if wearables.state == .streaming {
                Divider().overlay(Color.white.opacity(0.08))
                C2AMenuRow(icon: "camera.fill", title: s.capturePhoto,
                           subtitle: s.capturePhotoSub) {
                    wearables.capturePhoto()
                }
            }
        }
    }

    private func trigger(_ intent: VoiceIntent) {
        let now = Date()
        let event = VoiceIntentEvent(intent: intent, transcript: "botão",
                                     wakeAt: now, commandAt: now)
        Task { await viewModel.handle(event, trigger: "button") }
    }
}

/// Separate subview so changes to the nested MetricsRecorder refresh the UI.
private struct MetricsCard: View {
    @ObservedObject var metrics: MetricsRecorder
    let s: L10n

    var body: some View {
        C2ACard {
            Text(s.metricsTitle)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
            C2AMetricTile(caption: s.interactions,
                          value: "\(metrics.rowCount)",
                          icon: "chart.bar.fill")
            HStack(spacing: 12) {
                ShareLink(item: metrics.fileURL) {
                    Label(s.exportCSV, systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(C2AOutlineButtonStyle(tint: .c2aAccent))
                Button {
                    metrics.clear()
                } label: {
                    Label(s.clear, systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(C2AOutlineButtonStyle(tint: .c2aDanger))
            }
        }
    }
}

#Preview {
    ContentView()
}
