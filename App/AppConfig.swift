import Foundation

enum AppConfig {
    /// Test API with the Smart Glass endpoints (article experiments).
    /// HTTP only — covered by an ATS exception in Info.plist.
    static let apiBaseURL = URL(string: "http://testes.conect2ai.dca.ufrn.br:8000")!

    /// Driver-behavior evaluation window ("como estou dirigindo?").
    static let behaviorWindowSeconds = 120
}
