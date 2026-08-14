import Foundation
import Testing
@testable import Conect2AICore

private let driverBehaviorJSON = Data("""
{
  "time_session": "2026-08-09T14:00:00",
  "last_sample_at": "2026-08-09T14:12:30",
  "window": {
    "seconds": 120,
    "window_start": "2026-08-09T14:10:30",
    "window_end": "2026-08-09T14:12:30",
    "predominant_behavior": "aggressive",
    "distribution": {"cautious": 10.0, "normal": 20.0, "aggressive": 70.0},
    "sample_count": 120
  },
  "trip": {
    "time_per_behavior": {"cautious": 120.0, "normal": 480.0, "aggressive": 150.0},
    "sample_count": 750
  }
}
""".utf8)

private let tripSummaryJSON = Data("""
{
  "trip_id": 42,
  "time_session": "2026-08-09T14:00:00",
  "total_distance": 12.482,
  "total_time": "PT45M12S",
  "total_time_seconds": 2712.0,
  "speed": {"avg": 38.4, "max": 92.0},
  "fuel_prediction": "Gasolina",
  "fuel_model_prediction_prob": 0.87,
  "emissions": {"total_g": 2450.32, "emission_by_km": 196.31, "classification": "E"},
  "driver_behavior": {"cautious": 120.0, "normal": 2400.0, "aggressive": 192.0},
  "email_sent": false
}
""".utf8)

struct SmartGlassModelTests {

    @Test func driverBehaviorDecodesSpecExample() throws {
        let response = try JSONDecoder().decode(DriverBehaviorResponse.self, from: driverBehaviorJSON)
        #expect(response.window.predominantBehavior == "aggressive")
        #expect(response.window.seconds == 120)
        #expect(response.window.distribution["aggressive"] == 70.0)
        #expect(response.trip?.sampleCount == 750)
    }

    @Test func tripSummaryDecodesSpecExample() throws {
        let summary = try JSONDecoder().decode(SmartGlassTripSummary.self, from: tripSummaryJSON)
        #expect(summary.tripId == 42)
        #expect(summary.emissions?.classification == "E")
        #expect(abs((summary.emissions?.emissionByKm ?? 0) - 196.31) < 0.001)
        #expect(summary.driverBehavior?["normal"] == 2400.0)
    }
}

struct SmartGlassFormatterTests {
    private let formatter = SmartGlassFormatter()

    @Test func driverBehaviorSpeechNamesWindowAndPredominantClass() throws {
        let response = try JSONDecoder().decode(DriverBehaviorResponse.self, from: driverBehaviorJSON)
        let speech = formatter.spokenDriverBehavior(response)
        #expect(speech.contains("2 minutos"))
        #expect(speech.contains("predominantemente agressiva"))
        #expect(speech.contains("70% agressiva"))
        #expect(speech.contains("10% cautelosa"))
    }

    @Test func driverBehaviorSpeechHandlesEmptyWindow() throws {
        let json = Data("""
        {"window": {"seconds": 120, "distribution": {}, "sample_count": 0}}
        """.utf8)
        let response = try JSONDecoder().decode(DriverBehaviorResponse.self, from: json)
        #expect(formatter.spokenDriverBehavior(response).contains("não tenho dados"))
    }

    @Test func emissionsFallbackSpeechUsesLastTripAndSaysSo() throws {
        let json = Data("""
        {
          "time_session": "2024-12-19T08:28:08",
          "total_distance": 114.6, "total_time": 2620.0,
          "speed": {"series": [], "statistics": {"avg": 34.0, "max": 95.0}},
          "emission_by_km": 35.57, "emission_classification": "A"
        }
        """.utf8)
        let trip = try JSONDecoder().decode(TripSummary.self, from: json)
        let speech = formatter.spokenEmissions(fromLastTrip: trip)
        #expect(speech.contains("Sem viagem ativa"))
        #expect(speech.contains("última viagem"))
        #expect(speech.contains("36 gramas de CO2 por quilômetro"))
        #expect(speech.contains("Classificação A"))
    }

    @Test func realtimeEmissionsDecodeAndSpeak() throws {
        let json = Data("""
        {
          "time_session": "2026-08-12T14:00:00",
          "last_sample_at": "2026-08-12T14:23:41",
          "emissions": {"total_g": 1240.5, "emission_by_km": 98.2, "classification": "B"}
        }
        """.utf8)
        let realtime = try JSONDecoder().decode(SmartGlassEmissions.self, from: json)
        #expect(realtime.lastSampleAt == "2026-08-12T14:23:41")
        let speech = formatter.spokenEmissions(realtime)
        #expect(speech.contains("98 gramas de CO2 por quilômetro"))
        #expect(speech.contains("1,2 quilos"))
        #expect(speech.contains("classificação é B"))
    }

    @Test func emissionsSpeechReportsRateTotalAndClassification() throws {
        let summary = try JSONDecoder().decode(SmartGlassTripSummary.self, from: tripSummaryJSON)
        let speech = formatter.spokenEmissions(summary)
        #expect(speech.contains("196 gramas de CO2 por quilômetro"))
        #expect(speech.contains("2,5 quilos"))
        #expect(speech.contains("classificação é E"))
    }

    @Test func tripSummarySpeechCoversDistanceSpeedFuelEmissionsAndBehavior() throws {
        let summary = try JSONDecoder().decode(SmartGlassTripSummary.self, from: tripSummaryJSON)
        let speech = formatter.spokenTripSummary(summary)
        #expect(speech.contains("12,5 quilômetros"))
        #expect(speech.contains("45 minutos"))
        #expect(speech.contains("média de 38"))
        #expect(speech.contains("Gasolina"))
        #expect(speech.contains("classificação E"))
        #expect(speech.contains("88% do tempo normal"))
    }
}

struct EnglishFormatterTests {
    private let formatter = SmartGlassFormatter(language: .enUS)

    @Test func driverBehaviorSpeaksEnglishWithEnglishLabels() throws {
        let response = try JSONDecoder().decode(DriverBehaviorResponse.self, from: driverBehaviorJSON)
        let speech = formatter.spokenDriverBehavior(response)
        #expect(speech.contains("In the last 2 minutes"))
        #expect(speech.contains("predominantly aggressive"))
        #expect(speech.contains("70% aggressive"))
        #expect(speech.contains("10% cautious"))
    }

    @Test func tripSummarySpeaksEnglishWithPointDecimals() throws {
        let summary = try JSONDecoder().decode(SmartGlassTripSummary.self, from: tripSummaryJSON)
        let speech = formatter.spokenTripSummary(summary)
        #expect(speech.contains("12.5 kilometers in 45 minutes"))
        #expect(speech.contains("Average speed of 38"))
        #expect(speech.contains("rating E"))
        #expect(speech.contains("normal 88% of the time"))
    }

    @Test func lastTripFormatterSpeaksEnglish() throws {
        let json = Data("""
        {
          "time_session": "2024-12-19T08:28:08",
          "total_distance": 114.64, "total_time": 2620.0,
          "speed": {"series": [], "statistics": {"avg": 34.0, "max": 95.0}},
          "fuel_prediction": "Gasolina", "emission_classification": "A"
        }
        """.utf8)
        let trip = try JSONDecoder().decode(TripSummary.self, from: json)
        let speech = TripSummaryFormatter(language: .enUS).spokenSummary(for: trip)
        #expect(speech.contains("Your last trip covered 114.6 kilometers in 44 minutes"))
        #expect(speech.contains("Emission rating: A"))
    }
}

struct VoiceIntentTests {

    @Test func englishQuestionsMapToIntents() {
        #expect(VoiceIntent.parse("how am i driving") == .drivingBehavior)
        #expect(VoiceIntent.parse("how am i emitting") == .emissions)
        #expect(VoiceIntent.parse("trip summary") == .tripSummary)
    }

    @Test func asrMishearingsOfEmittingStillMapToEmissions() {
        // en-US recognizer over HFP audio: "emitting" → "meeting"/"mission".
        #expect(VoiceIntent.parse("how am i meeting") == .emissions)
        #expect(VoiceIntent.parse("how am i in meeting") == .emissions)
        #expect(VoiceIntent.parse("my mission") == .emissions)
    }

    @Test func drivingQuestionsMapToDriverBehavior() {
        #expect(VoiceIntent.parse("como estou dirigindo") == .drivingBehavior)
        #expect(VoiceIntent.parse("como esta minha conducao") == .drivingBehavior)
        #expect(VoiceIntent.parse("comportamento") == .drivingBehavior)
    }

    @Test func emissionQuestionsMapToEmissions() {
        #expect(VoiceIntent.parse("como estou emitindo") == .emissions)
        #expect(VoiceIntent.parse("qual minha emissao") == .emissions)
        #expect(VoiceIntent.parse("quanto co2") == .emissions)
    }

    @Test func summaryQuestionsMapToTripSummary() {
        #expect(VoiceIntent.parse("resumo da viagem") == .tripSummary)
        #expect(VoiceIntent.parse("resumo de viagem") == .tripSummary)
        #expect(VoiceIntent.parse("como foi minha ultima viagem") == .tripSummary)
    }

    @Test func specificIntentsWinOverGenericSummary() {
        // "viagem" appears, but the specific token decides.
        #expect(VoiceIntent.parse("como estou dirigindo nessa viagem") == .drivingBehavior)
        #expect(VoiceIntent.parse("emissao da viagem") == .emissions)
    }

    @Test func unrelatedTextParsesToNil() {
        #expect(VoiceIntent.parse("bom dia") == nil)
    }
}
