#if os(iOS)
import AVFoundation
import Foundation
import MusicUnderstanding

struct BreeTrackAudioAnalysis: Codable, Sendable {
    let analyzedAt: Date
    let beatsPerMinute: Double?
    let pace: Double?
    let integratedLoudness: Double?
    let vocalActivity: Double
    let drumActivity: Double
    let bassActivity: Double
    let key: String?
    let mixScores: [String: Double]
    var mixTags: [String]? = nil

    var suggestedMixes: [String] {
        if let mixTags { return mixTags }
        let matched = mixScores.filter { $0.value >= 0.56 }.sorted { $0.value > $1.value }.map(\.key)
        return matched.isEmpty ? mixScores.sorted { $0.value > $1.value }.prefix(2).map(\.key) : matched
    }
}

enum BreeTrackAudioAnalyzer {
    static func analyze(url: URL, genres: [String]) async throws -> BreeTrackAudioAnalysis {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let session = try await MusicUnderstandingSession(asset: asset)
        let result = try await session.analyze(for: [
            .pace, .rhythm, .instrumentActivity, .loudness, .key
        ])

        let pace = mean(result.pace?.ranges.map(\.value) ?? [])
        let bpm = result.rhythm?.beatsPerMinute.map(Double.init)
        let loudness = result.loudness.map { Double($0.integrated.value) }
        let activity = result.instrumentActivity?.activity ?? [:]
        let vocals = mean(activity[.vocal]?.map(\.value) ?? []) ?? 0
        let drums = mean(activity[.drum]?.map(\.value) ?? []) ?? 0
        let bass = mean(activity[.bass]?.map(\.value) ?? []) ?? 0
        let key = result.key?.ranges.first.map { "\($0.value.tonic.rawValue) \($0.value.mode.rawValue)" }
        let scores = makeScores(
            bpm: bpm,
            pace: pace,
            loudness: loudness,
            vocals: vocals,
            drums: drums,
            bass: bass,
            key: key,
            genres: genres
        )
        let matchedTags = scores
            .filter { $0.value >= 0.56 }
            .sorted { $0.value > $1.value }
            .map(\.key)
        let mixTags = matchedTags.isEmpty
            ? scores.sorted { $0.value > $1.value }.prefix(2).map(\.key)
            : matchedTags

        return BreeTrackAudioAnalysis(
            analyzedAt: .now,
            beatsPerMinute: bpm,
            pace: pace,
            integratedLoudness: loudness,
            vocalActivity: vocals,
            drumActivity: drums,
            bassActivity: bass,
            key: key,
            mixScores: scores,
            mixTags: mixTags
        )
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func mean(_ values: [Float]) -> Double? {
        mean(values.map(Double.init))
    }

    nonisolated private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func bandFit(_ value: Double?, _ range: ClosedRange<Double>) -> Double {
        guard let value else { return 0.45 }
        if range.contains(value) { return 1 }
        let distance = value < range.lowerBound ? range.lowerBound - value : value - range.upperBound
        return clamp(1 - distance / max(24, range.upperBound - range.lowerBound))
    }

    private static func makeScores(
        bpm: Double?,
        pace: Double?,
        loudness: Double?,
        vocals: Double,
        drums: Double,
        bass: Double,
        key: String?,
        genres: [String]
    ) -> [String: Double] {
        let tempo = bpm ?? pace
        let energyFromLoudness = loudness.map { clamp(($0 + 36) / 25) }
        let energyFromPace = pace.map { clamp($0 / 150) }
        let energy = energyFromLoudness ?? energyFromPace ?? 0.5
        let paceEnergy = energyFromPace ?? energy
        let instrumental = 1 - clamp(vocals)
        let minor = key?.localizedCaseInsensitiveContains("minor") == true ? 1.0 : 0.25
        let genreText = genres.joined(separator: " ").lowercased()
        func hasGenre(_ values: [String]) -> Double { values.contains(where: genreText.contains) ? 1.0 : 0.0 }

        return [
            "Morning Coffee & Ease-In": 0.42 * bandFit(tempo, 55...100) + 0.25 * (1 - energy) + 0.18 * (1 - drums) + 0.15 * hasGenre(["acoustic", "folk", "indie", "piano"]),
            "Deep Work & Coding Focus": 0.38 * instrumental + 0.30 * (1 - paceEnergy) + 0.22 * (1 - drums) + 0.10 * hasGenre(["lofi", "lo-fi", "ambient", "instrumental"]),
            "Midday Energy & Feel-Good Boost": 0.42 * bandFit(tempo, 110...125) + 0.25 * energy + 0.18 * drums + 0.15 * (1 - minor),
            "High-Intensity & Running": 0.38 * bandFit(tempo, 130...210) + 0.25 * paceEnergy + 0.20 * drums + 0.17 * bass,
            "Cooking & Hosting Dinner": 0.40 * bandFit(tempo, 75...115) + 0.22 * bass + 0.20 * (1 - abs(energy - 0.48)) + 0.18 * hasGenre(["soul", "bossa", "jazz", "funk"]),
            "Daytime Road Trip & Cruising": 0.38 * bandFit(tempo, 95...140) + 0.24 * drums + 0.22 * energy + 0.16 * hasGenre(["rock", "country", "americana", "pop"]),
            "Late-Night Drive": 0.30 * bandFit(tempo, 70...120) + 0.24 * bass + 0.24 * minor + 0.22 * (1 - abs(energy - 0.48)),
            "Gaming & Immersive Sessions": 0.32 * instrumental + 0.28 * bandFit(tempo, 80...145) + 0.22 * drums + 0.18 * hasGenre(["electronic", "synth", "soundtrack", "ambient"]),
            "Evening Unwind & Lounge": 0.30 * bandFit(tempo, 55...105) + 0.28 * (1 - paceEnergy) + 0.22 * (1 - drums) + 0.20 * hasGenre(["jazz", "lounge", "chill", "downtempo"]),
            "Sleep & Deep Relaxation": 0.32 * bandFit(tempo, 30...70) + 0.28 * (1 - paceEnergy) + 0.22 * (1 - drums) + 0.18 * (1 - vocals)
        ].mapValues(clamp)
    }
}
#endif
