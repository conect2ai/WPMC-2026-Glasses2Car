import Foundation

/// Appends one CSV row per voice interaction to Documents/smartglass_metrics.csv.
/// The file is exposed through the Files app (`UIFileSharingEnabled`) and the
/// share button in the UI, ready for pandas/matplotlib on the analysis side.
@MainActor
final class MetricsRecorder: ObservableObject {
    @Published private(set) var rowCount = 0

    let fileURL: URL

    static let header = [
        "interaction_id", "trigger", "intent", "endpoint", "transcript",
        "t_wake", "t_command", "asr_ms",
        "t_request_sent", "lat_sent", "lon_sent",
        "t_response_received", "lat_recv", "lon_recv",
        "api_ms", "api_error", "req_bytes_est", "resp_body_bytes", "format_ms",
        "t_tts_requested", "tts_synthesis_delay_ms", "tts_duration_ms", "spoken_chars",
        "total_ms",
        "cpu_pct", "mem_mb", "thermal", "battery_pct", "glasses_thermal",
        "window_start", "window_end", "last_sample_at",
        "spoken_text", "api_raw_response",
    ].joined(separator: ",") + "\n"

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("smartglass_metrics.csv")
        migrateIfHeaderChanged()
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? Self.header.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            rowCount = max(0, content.split(separator: "\n").count - 1)
        }
    }

    /// When the column set evolves, park the old file aside instead of mixing
    /// row formats in one CSV.
    private func migrateIfHeaderChanged() {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
              let firstLine = content.split(separator: "\n", maxSplits: 1).first,
              firstLine + "\n" != Self.header else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("smartglass_metrics_old_\(stamp).csv")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }

    func append(_ fields: [String]) {
        let line = fields.map(escape).joined(separator: ",") + "\n"
        guard let data = line.data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
        rowCount += 1
    }

    func clear() {
        try? Self.header.write(to: fileURL, atomically: true, encoding: .utf8)
        rowCount = 0
    }

    private func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
