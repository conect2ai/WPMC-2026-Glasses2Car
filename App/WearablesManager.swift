import Foundation
import UIKit
import MWDATCore
import MWDATCamera
import MWDATDisplay
import Conect2AICore

/// Owns the connection to the glasses: device session, camera stream and
/// photo capture. When the user captures a photo on the glasses, the photo is
/// published so the app can react (e.g. fetch and speak the trip summary).
@MainActor
final class WearablesManager: ObservableObject {
    enum GlassesState: String {
        case idle, starting, streaming, paused, stopped
    }

    @Published private(set) var state: GlassesState = .idle
    @Published private(set) var lastPhoto: UIImage?
    @Published private(set) var dashboardStatus: String?
    @Published private(set) var registrationStatus: String?
    @Published private(set) var connectionStatus: String?

    /// Fired whenever the glasses deliver a captured photo.
    var onPhotoCaptured: ((Data) -> Void)?

    private var session: DeviceSession?
    private var display: Display?
    private var captureAction: (() -> Void)?
    private var listenerTokens: [Any] = []
    private var knownDevices: [DeviceIdentifier] = []
    private var observingDeviceState = false

    /// Latest glasses thermal level, for the metrics CSV. The DAT SDK exposes
    /// only thermal state per device — no battery/CPU/memory of the glasses.
    static private(set) var latestGlassesThermal: String?

    /// One-time app linking with real glasses: deeplinks the user to the
    /// Meta AI app for confirmation. Not needed with Mock Device Kit
    /// (registration is simulated there).
    func startGlassesRegistration() {
        Task { [weak self] in
            do {
                try await Wearables.shared.startRegistration()
                self?.registrationStatus = "Confirme no app Meta AI…"
            } catch {
                self?.registrationStatus = "Falha ao iniciar registro: \(error)"
            }
        }
    }

    /// Completes the registration round-trip when Meta AI calls us back via
    /// the conect2aiglasses:// URL scheme.
    func handleCallback(url: URL) {
        Task {
            _ = try? await Wearables.shared.handleUrl(url)
        }
    }

    /// Mirrors the SDK registration state into the UI (and stdout for
    /// cable-attached debugging via `devicectl process launch --console`).
    func observeRegistration() {
        Task { [weak self] in
            for await regState in Wearables.shared.registrationStateStream() {
                print("MWDAT registration state:", regState)
                self?.registrationStatus = Self.describe(regState)
            }
        }
        Task { [weak self] in
            for await devices in Wearables.shared.devicesStream() {
                print("MWDAT devices:", devices)
                Self.logDeviceDetails(devices)
                self?.knownDevices = devices
                if let first = devices.first {
                    self?.observeDeviceState(first)
                }
            }
        }
    }

    /// Streams the glasses' DeviceState (thermal level) into the metrics.
    private func observeDeviceState(_ identifier: DeviceIdentifier) {
        guard !observingDeviceState else { return }
        observingDeviceState = true
        Task {
            for await state in Wearables.shared.deviceStateStream(for: identifier) {
                let thermal = String(describing: state.thermalLevel)
                print("MWDAT glasses thermal:", thermal)
                Self.latestGlassesThermal = thermal
            }
        }
    }

    private static func describe(_ state: RegistrationState) -> String {
        let pt = LanguageSetting.current == .ptBR
        switch state {
        case .unavailable: return pt ? "Meta AI indisponível" : "Meta AI unavailable"
        case .available: return pt ? "Pronto para registrar" : "Ready to register"
        case .registering: return pt ? "Registrando…" : "Registering…"
        case .registered: return pt ? "Registrado no Meta AI ✓" : "Registered with Meta AI ✓"
        @unknown default: return String(describing: state)
        }
    }

    /// Prints link state and compatibility for each known device — the two
    /// fields that explain a `noEligibleDevice` error.
    nonisolated static func logDeviceDetails(_ identifiers: [DeviceIdentifier]) {
        for id in identifiers {
            guard let device = Wearables.shared.deviceForIdentifier(id) else {
                print("MWDAT device \(id): not resolvable")
                continue
            }
            print("MWDAT device \(device.nameOrId()) — link: \(device.linkState), compat: \(device.compatibility()), type: \(device.deviceType())")
        }
    }

    /// Ensures camera permission (deeplinks to Meta AI on first use), then
    /// creates the device session and camera stream. Every failure is surfaced
    /// in `connectionStatus` — never fail silently.
    func connectAndStream() {
        guard session == nil else { return }
        let pt = LanguageSetting.current == .ptBR
        connectionStatus = pt ? "Verificando permissão de câmera…" : "Checking camera permission…"
        Task { [weak self] in
            guard let self else { return }
            do {
                var status = try await Wearables.shared.checkPermissionStatus(.camera)
                print("MWDAT camera permission:", status)
                if status != .granted {
                    self.connectionStatus = pt
                        ? "Confirme a permissão de câmera no Meta AI…"
                        : "Confirm the camera permission in Meta AI…"
                    status = try await Wearables.shared.requestPermission(.camera)
                    print("MWDAT camera permission after request:", status)
                }
                guard status == .granted else {
                    self.connectionStatus = pt
                        ? "Permissão de câmera negada no Meta AI."
                        : "Camera permission denied in Meta AI."
                    return
                }
                self.connectionStatus = nil
                try self.openSessionAndStream()
            } catch {
                print("MWDAT connect error:", error)
                let ids = Array(await Wearables.shared.devicesStream().first(where: { _ in true }) ?? [])
                Self.logDeviceDetails(ids)
                self.connectionStatus = (pt ? "Erro ao conectar: " : "Connection error: ") + String(describing: error)
            }
        }
    }

    private func openSessionAndStream() throws {
        let wearables = Wearables.shared
        // Prefer pinning the session to a device we can see is connected —
        // AutoDeviceSelector resolves asynchronously and can report
        // noEligibleDevice even when a compatible device is linked.
        let connected = knownDevices.first { id in
            wearables.deviceForIdentifier(id)?.linkState == .connected
        }
        let selector: any DeviceSelector
        if let connected {
            print("MWDAT using SpecificDeviceSelector for", connected)
            selector = SpecificDeviceSelector(device: connected)
        } else {
            print("MWDAT falling back to AutoDeviceSelector")
            selector = AutoDeviceSelector(wearables: wearables)
        }
        let session = try wearables.createSession(deviceSelector: selector)
        self.session = session
        state = .starting

        let config = StreamConfiguration(
            videoCodec: VideoCodec.raw,
            resolution: StreamingResolution.low,
            frameRate: 24)
        guard let stream = try session.addStream(config: config) else {
            state = .stopped
            connectionStatus = "Não foi possível criar o stream de câmera."
            return
        }

        let stateToken = stream.statePublisher.listen { [weak self] streamState in
            print("MWDAT stream state:", streamState)
            Task { @MainActor in
                switch streamState {
                case .streaming: self?.state = .streaming
                case .paused: self?.state = .paused
                case .stopped, .stopping: self?.state = .stopped
                default: break
                }
            }
        }

        let photoToken = stream.photoDataPublisher.listen { [weak self] photoData in
            let data = photoData.data
            Task { @MainActor in
                self?.lastPhoto = UIImage(data: data)
                self?.onPhotoCaptured?(data)
            }
        }

        listenerTokens = [stateToken, photoToken]
        captureAction = { stream.capturePhoto(format: .jpeg) }

        try session.start()
        stream.start()
    }

    /// Captures a single frame from the active stream.
    func capturePhoto() {
        captureAction?()
    }

    /// Renders the driver dashboard on the glasses' lens display.
    /// Only Meta Ray-Ban Display glasses have a display; on other models the
    /// SDK throws and we surface a readable status instead of failing silently.
    func showDashboard(for trip: TripSummary) async {
        guard let session else {
            dashboardStatus = "Conecte os óculos primeiro."
            return
        }
        do {
            let display: Display
            if let existing = self.display {
                display = existing
            } else {
                display = try session.addDisplay()
                display.start()
                self.display = display
            }
            try await display.send(GlassesDashboard.makeView(for: trip))
            dashboardStatus = "Painel enviado para a lente."
        } catch {
            dashboardStatus = "Este óculos não tem display (requer Meta Ray-Ban Display): \(error)"
        }
    }

    func disconnect() {
        display?.stop()
        display = nil
        listenerTokens.removeAll()
        captureAction = nil
        session = nil
        state = .idle
    }
}
