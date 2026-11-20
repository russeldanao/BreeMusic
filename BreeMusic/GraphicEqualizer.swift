#if os(iOS)
import AVFoundation
import CoreMedia
import Foundation
import MediaToolbox
import Synchronization

struct BreeEQProcessingOptions: Codable, Equatable, Sendable {
    var highPassEnabled = false
    var highPassFrequency: Float = 30
    var lowPassEnabled = false
    var lowPassFrequency: Float = 18_000
    var lowShelfEnabled = false
    var lowShelfGain: Float = 0
    var highShelfEnabled = false
    var highShelfGain: Float = 0
    var compressorEnabled = false
    var compressorThreshold: Float = -18
    var compressorRatio: Float = 3
    var limiterEnabled = false
    var limiterCeiling: Float = -1
    var leftDelayMilliseconds: Float = 0
    var rightDelayMilliseconds: Float = 0
    var invertLeftPolarity = false
    var invertRightPolarity = false
    var loudnessCompensationEnabled = false

    private enum CodingKeys: String, CodingKey {
        case highPassEnabled, highPassFrequency, lowPassEnabled, lowPassFrequency
        case lowShelfEnabled, lowShelfGain, highShelfEnabled, highShelfGain
        case compressorEnabled, compressorThreshold, compressorRatio
        case limiterEnabled, limiterCeiling, leftDelayMilliseconds, rightDelayMilliseconds
        case invertLeftPolarity, invertRightPolarity, loudnessCompensationEnabled
    }

    init() { }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        highPassEnabled = try values.decodeIfPresent(Bool.self, forKey: .highPassEnabled) ?? false
        highPassFrequency = try values.decodeIfPresent(Float.self, forKey: .highPassFrequency) ?? 30
        lowPassEnabled = try values.decodeIfPresent(Bool.self, forKey: .lowPassEnabled) ?? false
        lowPassFrequency = try values.decodeIfPresent(Float.self, forKey: .lowPassFrequency) ?? 18_000
        lowShelfEnabled = try values.decodeIfPresent(Bool.self, forKey: .lowShelfEnabled) ?? false
        lowShelfGain = try values.decodeIfPresent(Float.self, forKey: .lowShelfGain) ?? 0
        highShelfEnabled = try values.decodeIfPresent(Bool.self, forKey: .highShelfEnabled) ?? false
        highShelfGain = try values.decodeIfPresent(Float.self, forKey: .highShelfGain) ?? 0
        compressorEnabled = try values.decodeIfPresent(Bool.self, forKey: .compressorEnabled) ?? false
        compressorThreshold = try values.decodeIfPresent(Float.self, forKey: .compressorThreshold) ?? -18
        compressorRatio = try values.decodeIfPresent(Float.self, forKey: .compressorRatio) ?? 3
        limiterEnabled = try values.decodeIfPresent(Bool.self, forKey: .limiterEnabled) ?? false
        limiterCeiling = try values.decodeIfPresent(Float.self, forKey: .limiterCeiling) ?? -1
        leftDelayMilliseconds = try values.decodeIfPresent(Float.self, forKey: .leftDelayMilliseconds) ?? 0
        rightDelayMilliseconds = try values.decodeIfPresent(Float.self, forKey: .rightDelayMilliseconds) ?? 0
        invertLeftPolarity = try values.decodeIfPresent(Bool.self, forKey: .invertLeftPolarity) ?? false
        invertRightPolarity = try values.decodeIfPresent(Bool.self, forKey: .invertRightPolarity) ?? false
        loudnessCompensationEnabled = try values.decodeIfPresent(Bool.self, forKey: .loudnessCompensationEnabled) ?? false
    }
}

struct BreeMixEQProfile: Sendable {
    let bandGains: [Float]
    let processing: BreeEQProcessingOptions

    static func make(mood: String, averageBPM: Double?) -> BreeMixEQProfile {
        let anchors: [(frequency: Double, width: Double, gain: Double)]
        switch mood {
        case "Morning Coffee & Ease-In": anchors = [(130, 1.0, 0.45), (420, 0.9, -0.25), (7_000, 1.1, 0.2)]
        case "Deep Work & Coding Focus": anchors = [(80, 0.9, -0.25), (250, 0.9, -0.2), (1_600, 1.0, 0.25)]
        case "Midday Energy & Feel-Good Boost": anchors = [(100, 0.9, 0.4), (350, 0.8, -0.3), (3_000, 0.9, 0.35)]
        case "High-Intensity & Running": anchors = [(70, 0.9, 0.65), (300, 0.8, -0.4), (3_500, 0.9, 0.45)]
        case "Cooking & Hosting Dinner": anchors = [(120, 1.0, 0.4), (400, 0.8, -0.25), (2_500, 1.0, 0.25)]
        case "Daytime Road Trip & Cruising": anchors = [(95, 0.9, 0.45), (350, 0.8, -0.3), (2_500, 0.9, 0.35)]
        case "Late-Night Drive": anchors = [(75, 0.9, 0.35), (280, 0.8, -0.4), (6_000, 1.0, -0.15)]
        case "Gaming & Immersive Sessions": anchors = [(90, 0.9, 0.25), (500, 0.9, -0.2), (4_000, 0.9, 0.3)]
        case "Evening Unwind & Lounge": anchors = [(125, 1.0, 0.35), (450, 0.9, -0.25), (6_000, 1.0, 0.15)]
        case "Sleep & Deep Relaxation": anchors = [(110, 1.0, 0.25), (500, 0.9, -0.2), (5_000, 1.0, -0.2)]
        default: anchors = []
        }

        let tempoScale: Double
        if let averageBPM, averageBPM > 0 {
            tempoScale = averageBPM < 85 ? 0.85 : averageBPM > 140 ? 0.75 : 1
        } else {
            tempoScale = 0.85
        }
        let gains = BreeEQSettings.frequencies.map { frequency -> Float in
            let hz = Double(frequency)
            let value = anchors.reduce(0.0) { total, anchor in
                let octaves = log2(hz / anchor.frequency)
                let weight = exp(-(octaves * octaves) / (2 * anchor.width * anchor.width))
                return total + anchor.gain * weight
            } * tempoScale
            return Float(min(1.0, max(-1.0, value)))
        }

        var processing = BreeEQProcessingOptions()
        if ["Midday Energy & Feel-Good Boost", "High-Intensity & Running"].contains(mood) {
            processing.compressorEnabled = true
            processing.compressorThreshold = -20
            processing.compressorRatio = 1.4
            processing.limiterEnabled = true
            processing.limiterCeiling = -1
        }
        return BreeMixEQProfile(bandGains: gains, processing: processing)
    }
}

struct BreeVirtualSpeaker: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var name: String
    var enabled = true
    var gain: Float = 0
    var highPassEnabled = false
    var highPassFrequency: Float = 80
    var lowPassEnabled = false
    var lowPassFrequency: Float = 20_000
    var delayMilliseconds: Float = 0
    var lowGain: Float = 0
    var midGain: Float = 0
    var highGain: Float = 0
    var inverted = false
    var limiterEnabled = true
    var limiterCeiling: Float = -1

    static let defaults: [BreeVirtualSpeaker] = [
        .init(id: 0, name: "Front Left", lowPassEnabled: true, lowPassFrequency: 3_000),
        .init(id: 1, name: "Front Right", lowPassEnabled: true, lowPassFrequency: 3_000),
        .init(id: 2, name: "Rear Left", lowPassEnabled: true, lowPassFrequency: 3_000),
        .init(id: 3, name: "Rear Right", lowPassEnabled: true, lowPassFrequency: 3_000),
        .init(id: 4, name: "Tweeter Left", highPassEnabled: true, highPassFrequency: 3_000),
        .init(id: 5, name: "Tweeter Right", highPassEnabled: true, highPassFrequency: 3_000)
    ]
}

fileprivate struct BreePackedMixGains: Equatable {
    let first: UInt64
    let second: UInt64
    let third: UInt64

    subscript(index: Int) -> UInt64 {
        switch index {
        case 0: first
        case 1: second
        default: third
        }
    }

    static let allOnes = BreePackedMixGains(first: .max, second: .max, third: .max)
}

final class BreeEQSettings: @unchecked Sendable {
    static let shared = BreeEQSettings()
    static let frequencies: [Float] = [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1_000, 1_250, 1_600, 2_000, 2_500, 3_150, 4_000, 5_000, 6_300, 8_000, 10_000, 12_500, 16_000, 20_000]

    private let packedValue0: Atomic<UInt64>
    private let packedValue1: Atomic<UInt64>
    private let packedValue2: Atomic<UInt64>
    private let qValue: Atomic<UInt32>
    private let packedProcessing: Atomic<UInt64>
    private let mixProfileActive: Atomic<UInt32>
    private let packedMixProfile0: Atomic<UInt64>
    private let packedMixProfile1: Atomic<UInt64>
    private let packedMixProfile2: Atomic<UInt64>
    private let packedMixProcessing: Atomic<UInt64>
    private let packedCarPosition: Atomic<UInt32>
    private let virtualWord0: Atomic<UInt64>
    private let virtualWord1: Atomic<UInt64>
    private let virtualWord2: Atomic<UInt64>
    private let virtualWord3: Atomic<UInt64>
    private let virtualWord4: Atomic<UInt64>
    private let virtualWord5: Atomic<UInt64>
    private let virtualFrequencyWord0: Atomic<UInt64>
    private let virtualFrequencyWord1: Atomic<UInt64>
    private let virtualFrequencyWord2: Atomic<UInt64>
    private let virtualFrequencyWord3: Atomic<UInt64>
    private let virtualFrequencyWord4: Atomic<UInt64>
    private let virtualFrequencyWord5: Atomic<UInt64>

    private init() {
        let enabled = UserDefaults.standard.object(forKey: "breeEQEnabled") as? Bool ?? false
        let storedGains = (UserDefaults.standard.array(forKey: "breeEQGains") as? [NSNumber])?.map(\.floatValue)
        let gains = Self.normalizedGains(storedGains)
        let packed = Self.pack(enabled: enabled, gains: gains)
        packedValue0 = Atomic(packed[0])
        packedValue1 = Atomic(packed[1])
        packedValue2 = Atomic(packed[2])
        let q = min(4, max(0.3, UserDefaults.standard.double(forKey: "breeEQParametricQ") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "breeEQParametricQ")))
        qValue = Atomic(UInt32((q * 100).rounded()))
        let options: BreeEQProcessingOptions
        if let data = UserDefaults.standard.data(forKey: "breeEQProcessingOptions"),
           let saved = try? JSONDecoder().decode(BreeEQProcessingOptions.self, from: data) {
            options = saved
        } else {
            options = BreeEQProcessingOptions()
        }
        packedProcessing = Atomic(Self.pack(options: options))
        mixProfileActive = Atomic(0)
        packedMixProfile0 = Atomic(0)
        packedMixProfile1 = Atomic(0)
        packedMixProfile2 = Atomic(0)
        packedMixProcessing = Atomic(0)
        let fader = min(1, max(-1, Float(UserDefaults.standard.double(forKey: "breeCarFader"))))
        let balance = min(1, max(-1, Float(UserDefaults.standard.double(forKey: "breeCarBalance"))))
        packedCarPosition = Atomic(Self.packCarPosition(fader: fader, balance: balance))
        let virtualSpeakers: [BreeVirtualSpeaker]
        if let data = UserDefaults.standard.data(forKey: "breeVirtualSpeakers"),
           let saved = try? JSONDecoder().decode([BreeVirtualSpeaker].self, from: data), saved.count == 6 {
            virtualSpeakers = saved
        } else {
            virtualSpeakers = BreeVirtualSpeaker.defaults
        }
        virtualWord0 = Atomic(Self.pack(virtualSpeakers[0]))
        virtualWord1 = Atomic(Self.pack(virtualSpeakers[1]))
        virtualWord2 = Atomic(Self.pack(virtualSpeakers[2]))
        virtualWord3 = Atomic(Self.pack(virtualSpeakers[3]))
        virtualWord4 = Atomic(Self.pack(virtualSpeakers[4]))
        virtualWord5 = Atomic(Self.pack(virtualSpeakers[5]))
        virtualFrequencyWord0 = Atomic(Self.packFrequencies(virtualSpeakers[0]))
        virtualFrequencyWord1 = Atomic(Self.packFrequencies(virtualSpeakers[1]))
        virtualFrequencyWord2 = Atomic(Self.packFrequencies(virtualSpeakers[2]))
        virtualFrequencyWord3 = Atomic(Self.packFrequencies(virtualSpeakers[3]))
        virtualFrequencyWord4 = Atomic(Self.packFrequencies(virtualSpeakers[4]))
        virtualFrequencyWord5 = Atomic(Self.packFrequencies(virtualSpeakers[5]))
    }

    var enabled: Bool {
        currentWords[0] & 1 == 1
    }

    var gains: [Float] {
        let packed = currentWords
        return Self.frequencies.indices.map { Self.gain(from: packed, band: $0) }
    }

    var parametricQ: Float {
        Float(qValue.load(ordering: .relaxed)) / 100
    }

    var processingOptions: BreeEQProcessingOptions {
        Self.unpack(packedProcessing.load(ordering: .relaxed))
    }

    var carFader: Float {
        Self.unpackCarPosition(packedCarPosition.load(ordering: .relaxed)).fader
    }

    var carBalance: Float {
        Self.unpackCarPosition(packedCarPosition.load(ordering: .relaxed)).balance
    }

    var virtualSpeakers: [BreeVirtualSpeaker] {
        (0..<6).map { currentVirtualSpeaker($0) }
    }

    func setMixProfile(_ profile: BreeMixEQProfile?) {
        let packed = profile.map { Self.packMixGains($0.bandGains) } ?? [0, 0, 0]
        packedMixProfile0.store(packed[0], ordering: .relaxed)
        packedMixProfile1.store(packed[1], ordering: .relaxed)
        packedMixProfile2.store(packed[2], ordering: .relaxed)
        packedMixProcessing.store(profile.map { Self.pack(options: $0.processing) } ?? 0, ordering: .relaxed)
        mixProfileActive.store(profile.map { _ in UInt32(1) } ?? UInt32(0), ordering: .relaxed)
    }

    fileprivate var currentMixWords: BreePackedMixGains {
        BreePackedMixGains(
            first: packedMixProfile0.load(ordering: .relaxed),
            second: packedMixProfile1.load(ordering: .relaxed),
            third: packedMixProfile2.load(ordering: .relaxed)
        )
    }

    fileprivate var currentMixProcessingWord: UInt64 { packedMixProcessing.load(ordering: .relaxed) }
    fileprivate var hasMixProfile: Bool { mixProfileActive.load(ordering: .relaxed) != 0 }

    private var hasActiveProcessing: Bool {
        let baseWords = currentWords
        let baseGraphicEnabled = baseWords[0] & 1 == 1
        let mixWords = currentMixWords
        let mixIsActive = hasMixProfile
        let graphicHasGain = BreeEQSettings.frequencies.indices.contains { band in
            let baseGain = baseGraphicEnabled ? Self.gain(from: baseWords, band: band) : 0
            let mixGain = mixIsActive ? Self.mixGain(from: mixWords, band: band) : 0
            return abs(baseGain + mixGain) > 0.01
        }
        let options = Self.unpack(currentProcessingWord)
        let mixOptions = Self.unpack(currentMixProcessingWord)
        let processingIsActive = options.highPassEnabled
            || options.lowPassEnabled
            || options.lowShelfEnabled && abs(options.lowShelfGain) > 0.01
            || options.highShelfEnabled && abs(options.highShelfGain) > 0.01
            || options.compressorEnabled
            || options.limiterEnabled
            || options.loudnessCompensationEnabled
            || options.invertLeftPolarity
            || options.invertRightPolarity
            || options.leftDelayMilliseconds > 0
            || options.rightDelayMilliseconds > 0
        let position = Self.unpackCarPosition(currentCarPosition)
        let carPositionIsActive = abs(position.fader) > 0.001 || abs(position.balance) > 0.001
        let speakerIsActive = virtualSpeakers.contains { speaker in
            speaker.enabled && (
                abs(speaker.gain) > 0.01
                    || speaker.highPassEnabled
                    || speaker.lowPassEnabled
                    || abs(speaker.lowGain) > 0.01
                    || abs(speaker.midGain) > 0.01
                    || abs(speaker.highGain) > 0.01
                    || speaker.delayMilliseconds > 0
                    || speaker.inverted
                    || speaker.limiterEnabled
            )
        }
        let mixProcessingIsActive = mixIsActive && (
            mixOptions.compressorEnabled || mixOptions.limiterEnabled
                || mixOptions.lowShelfEnabled || mixOptions.highShelfEnabled
        )
        return graphicHasGain || processingIsActive || mixProcessingIsActive || carPositionIsActive || speakerIsActive
    }

    func update(enabled: Bool, gains: [Float], parametricQ: Float? = nil, processingOptions: BreeEQProcessingOptions? = nil, carFader: Float? = nil, carBalance: Float? = nil, virtualSpeakers: [BreeVirtualSpeaker]? = nil) {
        let normalizedValues = Self.normalizedGains(gains)
        let packed = Self.pack(enabled: enabled, gains: normalizedValues)
        packedValue0.store(packed[0], ordering: .relaxed)
        packedValue1.store(packed[1], ordering: .relaxed)
        packedValue2.store(packed[2], ordering: .relaxed)

        if let parametricQ {
            let q = min(4, max(0.3, parametricQ))
            qValue.store(UInt32((q * 100).rounded()), ordering: .relaxed)
            UserDefaults.standard.set(Double(q), forKey: "breeEQParametricQ")
        }
        if let processingOptions {
            let bounded = Self.bounded(processingOptions)
            packedProcessing.store(Self.pack(options: bounded), ordering: .relaxed)
            if let data = try? JSONEncoder().encode(bounded) {
                UserDefaults.standard.set(data, forKey: "breeEQProcessingOptions")
            }
        }
        if carFader != nil || carBalance != nil {
            let current = Self.unpackCarPosition(packedCarPosition.load(ordering: .relaxed))
            let fader = min(1, max(-1, carFader ?? current.fader))
            let balance = min(1, max(-1, carBalance ?? current.balance))
            packedCarPosition.store(Self.packCarPosition(fader: fader, balance: balance), ordering: .relaxed)
            UserDefaults.standard.set(Double(fader), forKey: "breeCarFader")
            UserDefaults.standard.set(Double(balance), forKey: "breeCarBalance")
        }
        if let virtualSpeakers, virtualSpeakers.count == 6 {
            let bounded = virtualSpeakers.enumerated().map { Self.bounded($0.element, id: $0.offset) }
            virtualWord0.store(Self.pack(bounded[0]), ordering: .relaxed)
            virtualWord1.store(Self.pack(bounded[1]), ordering: .relaxed)
            virtualWord2.store(Self.pack(bounded[2]), ordering: .relaxed)
            virtualWord3.store(Self.pack(bounded[3]), ordering: .relaxed)
            virtualWord4.store(Self.pack(bounded[4]), ordering: .relaxed)
            virtualWord5.store(Self.pack(bounded[5]), ordering: .relaxed)
            for index in bounded.indices {
                storeVirtualFrequencyWord(Self.packFrequencies(bounded[index]), at: index)
            }
            if let data = try? JSONEncoder().encode(bounded) {
                UserDefaults.standard.set(data, forKey: "breeVirtualSpeakers")
            }
        }

        UserDefaults.standard.set(enabled, forKey: "breeEQEnabled")
        UserDefaults.standard.set(normalizedValues.map(Double.init), forKey: "breeEQGains")
    }

    fileprivate var currentWords: [UInt64] {
        [packedValue0.load(ordering: .relaxed), packedValue1.load(ordering: .relaxed), packedValue2.load(ordering: .relaxed)]
    }

    fileprivate var currentProcessingWord: UInt64 { packedProcessing.load(ordering: .relaxed) }
    fileprivate var currentCarPosition: UInt32 { packedCarPosition.load(ordering: .relaxed) }

    fileprivate func currentVirtualSpeakerWord(_ index: Int) -> UInt64 {
        switch index {
        case 0: virtualWord0.load(ordering: .relaxed)
        case 1: virtualWord1.load(ordering: .relaxed)
        case 2: virtualWord2.load(ordering: .relaxed)
        case 3: virtualWord3.load(ordering: .relaxed)
        case 4: virtualWord4.load(ordering: .relaxed)
        default: virtualWord5.load(ordering: .relaxed)
        }
    }

    fileprivate func currentVirtualSpeaker(_ index: Int) -> BreeVirtualSpeaker {
        var speaker = Self.unpack(currentVirtualSpeakerWord(index), id: index)
        let frequencies = currentVirtualFrequencyWord(index)
        speaker.highPassFrequency = Float(bitPattern: UInt32(truncatingIfNeeded: frequencies))
        speaker.lowPassFrequency = Float(bitPattern: UInt32(truncatingIfNeeded: frequencies >> 32))
        return speaker
    }

    private func currentVirtualFrequencyWord(_ index: Int) -> UInt64 {
        switch index {
        case 0: virtualFrequencyWord0.load(ordering: .relaxed)
        case 1: virtualFrequencyWord1.load(ordering: .relaxed)
        case 2: virtualFrequencyWord2.load(ordering: .relaxed)
        case 3: virtualFrequencyWord3.load(ordering: .relaxed)
        case 4: virtualFrequencyWord4.load(ordering: .relaxed)
        default: virtualFrequencyWord5.load(ordering: .relaxed)
        }
    }

    private static func packFrequencies(_ source: BreeVirtualSpeaker) -> UInt64 {
        let value = bounded(source, id: source.id)
        return UInt64(value.highPassFrequency.bitPattern)
            | (UInt64(value.lowPassFrequency.bitPattern) << 32)
    }

    private func storeVirtualFrequencyWord(_ word: UInt64, at index: Int) {
        switch index {
        case 0: virtualFrequencyWord0.store(word, ordering: .relaxed)
        case 1: virtualFrequencyWord1.store(word, ordering: .relaxed)
        case 2: virtualFrequencyWord2.store(word, ordering: .relaxed)
        case 3: virtualFrequencyWord3.store(word, ordering: .relaxed)
        case 4: virtualFrequencyWord4.store(word, ordering: .relaxed)
        default: virtualFrequencyWord5.store(word, ordering: .relaxed)
        }
    }

    private static func bounded(_ source: BreeVirtualSpeaker, id: Int) -> BreeVirtualSpeaker {
        var value = source
        value.id = id
        value.name = BreeVirtualSpeaker.defaults[id].name
        value.gain = min(12, max(-12, value.gain))
        value.highPassFrequency = (min(4_000, max(20, value.highPassFrequency)) * 2).rounded() / 2
        value.lowPassFrequency = (min(20_000, max(1_000, value.lowPassFrequency)) * 2).rounded() / 2
        value.delayMilliseconds = (min(20, max(0, value.delayMilliseconds)) * 2).rounded() / 2
        value.gain = (min(12, max(-12, value.gain)) * 2).rounded() / 2
        value.lowGain = (min(12, max(-12, value.lowGain)) * 2).rounded() / 2
        value.midGain = (min(12, max(-12, value.midGain)) * 2).rounded() / 2
        value.highGain = (min(12, max(-12, value.highGain)) * 2).rounded() / 2
        value.limiterCeiling = (min(0, max(-12, value.limiterCeiling)) * 2).rounded() / 2
        return value
    }

    private static func pack(_ source: BreeVirtualSpeaker) -> UInt64 {
        let value = bounded(source, id: source.id)
        var bits: UInt64 = 0
        bits |= value.enabled ? 1 : 0
        bits |= UInt64(Int(((value.gain + 12) * 2).rounded())) << 1
        bits |= UInt64(value.highPassEnabled ? 1 : 0) << 7
        bits |= UInt64(value.lowPassEnabled ? 1 : 0) << 8
        bits |= UInt64(Int((value.delayMilliseconds * 2).rounded())) << 9
        bits |= UInt64(value.inverted ? 1 : 0) << 15
        bits |= UInt64(value.limiterEnabled ? 1 : 0) << 16
        bits |= UInt64(Int((-value.limiterCeiling * 2).rounded())) << 17
        bits |= UInt64(Int(((value.lowGain + 12) * 2).rounded())) << 22
        bits |= UInt64(Int(((value.midGain + 12) * 2).rounded())) << 28
        bits |= UInt64(Int(((value.highGain + 12) * 2).rounded())) << 34
        return bits
    }

    fileprivate static func unpack(_ bits: UInt64, id: Int) -> BreeVirtualSpeaker {
        var value = BreeVirtualSpeaker.defaults[id]
        value.enabled = bits & 1 != 0
        value.gain = Float(Int((bits >> 1) & 0x3F)) / 2 - 12
        value.highPassEnabled = bits & (1 << 7) != 0
        value.lowPassEnabled = bits & (1 << 8) != 0
        value.delayMilliseconds = Float((bits >> 9) & 0x3F) / 2
        value.inverted = bits & (1 << 15) != 0
        value.limiterEnabled = bits & (1 << 16) != 0
        value.limiterCeiling = -Float((bits >> 17) & 0x1F) / 2
        value.lowGain = Float(Int((bits >> 22) & 0x3F)) / 2 - 12
        value.midGain = Float(Int((bits >> 28) & 0x3F)) / 2 - 12
        value.highGain = Float(Int((bits >> 34) & 0x3F)) / 2 - 12
        return value
    }

    fileprivate static func gain(from packed: [UInt64], band: Int) -> Float {
        let offset = 1 + band * 5
        var encoded: UInt64 = 0
        for bit in 0..<5 {
            let position = offset + bit
            let isSet = (packed[position / 64] >> (position % 64)) & 1
            encoded |= isSet << bit
        }
        return Float(Int(encoded) - 12)
    }

    private static func normalizedGains(_ values: [Float]?) -> [Float] {
        guard let values, !values.isEmpty else { return Array(repeating: 0, count: frequencies.count) }
        if values.count == frequencies.count {
            return values.map { min(12, max(-12, $0)) }
        }
        // Migrate the older 10-band saved curve smoothly to the new 31 bands.
        return frequencies.indices.map { index in
            let sourcePosition = Float(index) * Float(max(values.count - 1, 1)) / Float(frequencies.count - 1)
            let lower = Int(sourcePosition)
            let upper = min(values.count - 1, lower + 1)
            let fraction = sourcePosition - Float(lower)
            let interpolated = values[lower] + (values[upper] - values[lower]) * fraction
            return min(12, max(-12, interpolated))
        }
    }

    private static func pack(enabled: Bool, gains: [Float]) -> [UInt64] {
        var packed: [UInt64] = [0, 0, 0]
        if enabled { packed[0] = 1 }
        for index in frequencies.indices {
            let quantized = min(12, max(-12, Int(gains[index].rounded()))) + 12
            let offset = 1 + index * 5
            for bit in 0..<5 where (quantized & (1 << bit)) != 0 {
                let position = offset + bit
                packed[position / 64] |= UInt64(1) << (position % 64)
            }
        }
        return packed
    }

    private static func packMixGains(_ gains: [Float]) -> [UInt64] {
        var packed: [UInt64] = [0, 0, 0]
        for index in frequencies.indices {
            let gain = gains.indices.contains(index) ? gains[index] : 0
            let encoded = min(31, max(0, Int((gain * 2).rounded()) + 16))
            let offset = index * 5
            for bit in 0..<5 where (encoded & (1 << bit)) != 0 {
                let position = offset + bit
                packed[position / 64] |= UInt64(1) << (position % 64)
            }
        }
        return packed
    }

    fileprivate static func mixGain(from packed: BreePackedMixGains, band: Int) -> Float {
        let offset = band * 5
        var encoded: UInt64 = 0
        for bit in 0..<5 {
            let position = offset + bit
            encoded |= ((packed[position / 64] >> (position % 64)) & 1) << bit
        }
        return Float(Int(encoded) - 16) / 2
    }

    private static let highPassStops: [Float] = [20, 30, 40, 50, 60, 80, 100, 120, 150, 200, 300, 400, 600, 800]
    private static let lowPassStops: [Float] = [2_000, 3_000, 4_000, 5_000, 6_000, 7_000, 8_000, 9_000, 10_000, 11_000, 12_000, 14_000, 16_000, 18_000, 20_000]

    private static func bounded(_ options: BreeEQProcessingOptions) -> BreeEQProcessingOptions {
        var value = options
        value.highPassFrequency = nearest(value.highPassFrequency, in: highPassStops)
        value.lowPassFrequency = nearest(value.lowPassFrequency, in: lowPassStops)
        value.lowShelfGain = min(12, max(-12, value.lowShelfGain))
        value.highShelfGain = min(12, max(-12, value.highShelfGain))
        value.compressorThreshold = min(0, max(-60, value.compressorThreshold))
        value.compressorRatio = min(20, max(1, value.compressorRatio))
        value.limiterCeiling = min(0, max(-12, value.limiterCeiling))
        value.leftDelayMilliseconds = min(20, max(0, value.leftDelayMilliseconds))
        value.rightDelayMilliseconds = min(20, max(0, value.rightDelayMilliseconds))
        return value
    }

    private static func packCarPosition(fader: Float, balance: Float) -> UInt32 {
        let faderValue = UInt32((min(1, max(-1, fader)) * 1000 + 1000).rounded())
        let balanceValue = UInt32((min(1, max(-1, balance)) * 1000 + 1000).rounded())
        return faderValue | (balanceValue << 11)
    }

    fileprivate static func unpackCarPosition(_ bits: UInt32) -> (fader: Float, balance: Float) {
        let fader = Float(bits & 0x7FF) / 1000 - 1
        let balance = Float((bits >> 11) & 0x7FF) / 1000 - 1
        return (min(1, max(-1, fader)), min(1, max(-1, balance)))
    }

    private static func nearest(_ frequency: Float, in stops: [Float]) -> Float {
        stops.min(by: { abs($0 - frequency) < abs($1 - frequency) }) ?? frequency
    }

    private static func pack(options: BreeEQProcessingOptions) -> UInt64 {
        let value = bounded(options)
        var bits: UInt64 = 0
        let flags = [value.highPassEnabled, value.lowPassEnabled, value.lowShelfEnabled, value.highShelfEnabled, value.compressorEnabled, value.limiterEnabled]
        for (index, enabled) in flags.enumerated() where enabled { bits |= UInt64(1) << index }
        let highPassIndex = highPassStops.firstIndex(of: value.highPassFrequency) ?? 1
        let lowPassIndex = lowPassStops.firstIndex(of: value.lowPassFrequency) ?? 13
        bits |= UInt64(highPassIndex & 0xF) << 6
        bits |= UInt64(lowPassIndex & 0xF) << 10
        bits |= UInt64(Int(value.lowShelfGain.rounded()) + 12) << 14
        bits |= UInt64(Int(value.highShelfGain.rounded()) + 12) << 19
        bits |= UInt64(Int(value.compressorThreshold.rounded() + 60)) << 24
        bits |= UInt64(Int(value.compressorRatio.rounded())) << 30
        bits |= UInt64(Int((-value.limiterCeiling).rounded())) << 35
        bits |= UInt64(value.loudnessCompensationEnabled ? 1 : 0) << 39
        bits |= UInt64(value.invertLeftPolarity ? 1 : 0) << 40
        bits |= UInt64(value.invertRightPolarity ? 1 : 0) << 41
        bits |= UInt64(Int((value.leftDelayMilliseconds * 10).rounded()) & 0xFF) << 42
        bits |= UInt64(Int((value.rightDelayMilliseconds * 10).rounded()) & 0xFF) << 50
        return bits
    }

    fileprivate static func unpack(_ bits: UInt64) -> BreeEQProcessingOptions {
        var value = BreeEQProcessingOptions()
        value.highPassEnabled = bits & 1 != 0
        value.lowPassEnabled = bits & 2 != 0
        value.lowShelfEnabled = bits & 4 != 0
        value.highShelfEnabled = bits & 8 != 0
        value.compressorEnabled = bits & 16 != 0
        value.limiterEnabled = bits & 32 != 0
        let highPassIndex = min(highPassStops.count - 1, max(0, Int((bits >> 6) & 0xF)))
        let lowPassIndex = min(lowPassStops.count - 1, max(0, Int((bits >> 10) & 0xF)))
        value.highPassFrequency = highPassStops[highPassIndex]
        value.lowPassFrequency = lowPassStops[lowPassIndex]
        value.lowShelfGain = Float(Int((bits >> 14) & 0x1F) - 12)
        value.highShelfGain = Float(Int((bits >> 19) & 0x1F) - 12)
        value.compressorThreshold = Float(Int((bits >> 24) & 0x3F) - 60)
        value.compressorRatio = Float(Int((bits >> 30) & 0x1F))
        value.limiterCeiling = -Float((bits >> 35) & 0xF)
        value.loudnessCompensationEnabled = bits & (1 << 39) != 0
        value.invertLeftPolarity = bits & (1 << 40) != 0
        value.invertRightPolarity = bits & (1 << 41) != 0
        value.leftDelayMilliseconds = Float((bits >> 42) & 0xFF) / 10
        value.rightDelayMilliseconds = Float((bits >> 50) & 0xFF) / 10
        return value
    }

    func audioMix() -> AVAudioMix? {
        // A disabled/flat DSP must be a true pass-through. Keeping an idle
        // MTAudioProcessingTap attached can make some Bluetooth receivers
        // advance the player timeline while producing silent output.
        guard hasActiveProcessing else { return nil }
        guard let tap = makeAudioTap() else { return nil }
        let parameters = AVMutableAudioMixInputParameters()
        parameters.trackID = 0 // AVAudioMixInputParametersTrackMixID
        parameters.audioTapProcessor = tap

        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }

    private func makeAudioTap() -> MTAudioProcessingTap? {
        let state = EQTapState(settings: self)
        let retainedState = Unmanaged.passRetained(state).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: retainedState,
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<EQTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, processingFormat in
                EQTapState.from(tap).prepare(format: processingFormat.pointee)
            },
            unprepare: { tap in
                EQTapState.from(tap).reset()
            },
            process: { tap, numberFrames, _, bufferList, numberFramesOut, flagsOut in
                var sourceFlags: MTAudioProcessingTapFlags = 0
                var sourceTimeRange = CMTimeRange.invalid
                let status = MTAudioProcessingTapGetSourceAudio(
                    tap,
                    numberFrames,
                    bufferList,
                    &sourceFlags,
                    &sourceTimeRange,
                    numberFramesOut
                )
                guard status == noErr else {
                    numberFramesOut.pointee = 0
                    flagsOut.pointee = 0
                    return
                }
                flagsOut.pointee = sourceFlags
                EQTapState.from(tap).process(bufferList: bufferList, frames: Int(numberFramesOut.pointee))
            }
        )

        var streamFormat = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &streamFormat,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            Unmanaged<EQTapState>.fromOpaque(retainedState).release()
            return nil
        }

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreateWithPreferredFormat(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            formatDescription,
            &tap
        )
        guard status == noErr else {
            Unmanaged<EQTapState>.fromOpaque(retainedState).release()
            return nil
        }
        return tap
    }
}

private final class EQTapState {
    private static let leftVirtualSpeakerIndices = [0, 2, 4]
    private static let rightVirtualSpeakerIndices = [1, 3, 5]
    private static let virtualMixWeights: [Float] = [0.45, 0.45, 0.45]
    private let settings: BreeEQSettings
    private var sampleRate: Float = 44_100
    private var channels = 2
    private var isFloatPCM = false
    private var isNonInterleaved = false
    private var lastWords = [UInt64.max, UInt64.max, UInt64.max]
    private var lastMixWords = BreePackedMixGains.allOnes
    private var lastQ: Float = -1
    private var lastProcessing: UInt64 = .max
    private var lastMixProcessing: UInt64 = .max
    private var lastMixActive = false
    private var filters: [[EQBiquad]] = []
    private var activeGraphicBands: [Int] = []
    private var highPassFilters: [EQBiquad] = []
    private var lowPassFilters: [EQBiquad] = []
    private var lowShelfFilters: [EQBiquad] = []
    private var highShelfFilters: [EQBiquad] = []
    private var compressorEnvelope: [Float] = []
    private var loudnessEnvelope: [Float] = []
    private var compressorAttackCoefficient: Float = 0
    private var compressorReleaseCoefficient: Float = 0
    private var compressorThresholdAmplitude: Float = 1
    private var limiterCeilingAmplitude: Float = 1
    private var alignmentBuffers: [[Float]] = []
    private var alignmentPositions: [Int] = []
    private var alignmentSamples: [Int] = []
    private var stereoHistory: [Float] = [0, 0]
    private var lastCarPosition: UInt32 = .max
    private var carFader: Float = 0
    private var carBalance: Float = 0
    private var lastVirtualSpeakers: [BreeVirtualSpeaker] = []
    private var virtualHPFilters: [EQBiquad] = []
    private var virtualLPFilters: [EQBiquad] = []
    private var virtualPEQFilters: [[EQBiquad]] = []
    private var virtualDelayBuffers: [[Float]] = []
    private var virtualDelayPositions: [Int] = []
    private var virtualDelaySamples: [Int] = []
    private var virtualLimiterCeilings: [Float] = []
    private var virtualConfigurations = BreeVirtualSpeaker.defaults
    private var virtualGainAmplitudes: [Float] = []

    init(settings: BreeEQSettings) {
        self.settings = settings
    }

    static func from(_ tap: MTAudioProcessingTap) -> EQTapState {
        Unmanaged<EQTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    func prepare(format: AudioStreamBasicDescription) {
        sampleRate = Float(format.mSampleRate)
        channels = max(1, Int(format.mChannelsPerFrame))
        isFloatPCM = format.mFormatID == kAudioFormatLinearPCM
            && format.mBitsPerChannel == 32
            && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        isNonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        filters = (0..<channels).map { _ in Array(repeating: EQBiquad(), count: BreeEQSettings.frequencies.count) }
        activeGraphicBands = []
        highPassFilters = Array(repeating: EQBiquad(), count: channels)
        lowPassFilters = Array(repeating: EQBiquad(), count: channels)
        lowShelfFilters = Array(repeating: EQBiquad(), count: channels)
        highShelfFilters = Array(repeating: EQBiquad(), count: channels)
        compressorEnvelope = Array(repeating: 0, count: channels)
        loudnessEnvelope = Array(repeating: 0, count: channels)
        alignmentBuffers = Array(repeating: Array(repeating: 0, count: Int(sampleRate * 0.020) + 2), count: channels)
        alignmentPositions = Array(repeating: 0, count: channels)
        alignmentSamples = Array(repeating: 0, count: channels)
        stereoHistory = Array(repeating: 0, count: channels)
        virtualHPFilters = Array(repeating: EQBiquad(), count: 6)
        virtualLPFilters = Array(repeating: EQBiquad(), count: 6)
        virtualPEQFilters = Array(repeating: Array(repeating: EQBiquad(), count: 3), count: 6)
        virtualDelayBuffers = Array(repeating: Array(repeating: 0, count: Int(sampleRate * 0.020) + 2), count: 6)
        virtualDelayPositions = Array(repeating: 0, count: 6)
        virtualDelaySamples = Array(repeating: 0, count: 6)
        virtualLimiterCeilings = Array(repeating: 1, count: 6)
        virtualGainAmplitudes = Array(repeating: 1, count: 6)
        lastWords = [UInt64.max, UInt64.max, UInt64.max]
        lastMixWords = BreePackedMixGains.allOnes
        lastQ = -1
        lastProcessing = .max
        lastMixProcessing = .max
        lastMixActive = false
        lastCarPosition = .max
        lastVirtualSpeakers = []
    }

    func reset() {
        for channel in filters.indices {
            for band in filters[channel].indices {
                filters[channel][band].clearHistory()
            }
        }
        for index in virtualPEQFilters.indices {
            for band in virtualPEQFilters[index].indices { virtualPEQFilters[index][band].clearHistory() }
            virtualHPFilters[index].clearHistory()
            virtualLPFilters[index].clearHistory()
            virtualDelayBuffers[index] = Array(repeating: 0, count: virtualDelayBuffers[index].count)
            virtualDelayPositions[index] = 0
        }
    }

    func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        let currentWords = settings.currentWords
        let mixWords = settings.currentMixWords
        let processingWord = settings.currentProcessingWord
        let mixProcessingWord = settings.currentMixProcessingWord
        let mixIsActive = settings.hasMixProfile
        var options = BreeEQSettings.unpack(processingWord)
        if mixIsActive {
            let mixOptions = BreeEQSettings.unpack(mixProcessingWord)
            if mixOptions.lowShelfEnabled {
                options.lowShelfEnabled = true
                options.lowShelfGain = min(12, max(-12, options.lowShelfGain + mixOptions.lowShelfGain))
            }
            if mixOptions.highShelfEnabled {
                options.highShelfEnabled = true
                options.highShelfGain = min(12, max(-12, options.highShelfGain + mixOptions.highShelfGain))
            }
            if mixOptions.compressorEnabled && !options.compressorEnabled {
                options.compressorEnabled = true
                options.compressorThreshold = mixOptions.compressorThreshold
                options.compressorRatio = mixOptions.compressorRatio
            }
            if mixOptions.limiterEnabled && !options.limiterEnabled {
                options.limiterEnabled = true
                options.limiterCeiling = mixOptions.limiterCeiling
            }
        }
        let baseGraphicEnabled = currentWords[0] & 1 == 1
        let graphicEnabled = baseGraphicEnabled || mixIsActive
        func effectiveBandGain(_ band: Int) -> Float {
            let baseGain = baseGraphicEnabled ? BreeEQSettings.gain(from: currentWords, band: band) : 0
            let mixGain = mixIsActive ? BreeEQSettings.mixGain(from: mixWords, band: band) : 0
            return min(12, max(-12, baseGain + mixGain))
        }
        let processingChanged = processingWord != lastProcessing
            || mixProcessingWord != lastMixProcessing
            || mixIsActive != lastMixActive
        let carPosition = settings.currentCarPosition
        let position = BreeEQSettings.unpackCarPosition(carPosition)
        // Avoid building temporary arrays on the real-time audio callback.
        // Allocations here can add audible glitches on older iPhones or busy routes.
        var hasSpeakerProcessing = false
        var speakersChanged = false
        for index in 0..<6 {
            let speaker = settings.currentVirtualSpeaker(index)
            if lastVirtualSpeakers.indices.contains(index), lastVirtualSpeakers[index] != speaker {
                speakersChanged = true
            }
            virtualConfigurations[index] = speaker
            if speaker.enabled && (
                abs(speaker.gain) > 0.01 || speaker.highPassEnabled || speaker.lowPassEnabled
                    || abs(speaker.lowGain) > 0.01 || abs(speaker.midGain) > 0.01
                    || abs(speaker.highGain) > 0.01 || speaker.delayMilliseconds > 0
                    || speaker.inverted || speaker.limiterEnabled
            ) { hasSpeakerProcessing = true }
        }
        let hasProcessing = options.highPassEnabled || options.lowPassEnabled || options.lowShelfEnabled || options.highShelfEnabled || options.compressorEnabled || options.limiterEnabled || options.loudnessCompensationEnabled || options.invertLeftPolarity || options.invertRightPolarity || options.leftDelayMilliseconds > 0 || options.rightDelayMilliseconds > 0 || abs(position.fader) > 0.001 || abs(position.balance) > 0.001 || hasSpeakerProcessing
        guard (graphicEnabled || hasProcessing), isFloatPCM, frames > 0 else { return }
        let q = settings.parametricQ

        if currentWords != lastWords || mixWords != lastMixWords || q != lastQ || processingChanged || carPosition != lastCarPosition {
            activeGraphicBands = graphicEnabled
                ? BreeEQSettings.frequencies.indices.filter { abs(effectiveBandGain($0)) > 0.01 }
                : []
            for channel in filters.indices {
                for band in filters[channel].indices {
                    filters[channel][band].configure(
                        frequency: BreeEQSettings.frequencies[band],
                        gain: graphicEnabled ? effectiveBandGain(band) : 0,
                        sampleRate: sampleRate,
                        q: q
                    )
                }
                highPassFilters[channel].configureHighPass(frequency: options.highPassFrequency, sampleRate: sampleRate)
                lowPassFilters[channel].configureLowPass(frequency: options.lowPassFrequency, sampleRate: sampleRate)
                lowShelfFilters[channel].configureShelf(frequency: 120, gain: options.lowShelfGain, sampleRate: sampleRate, isLowShelf: true)
                highShelfFilters[channel].configureShelf(frequency: 8_000, gain: options.highShelfGain, sampleRate: sampleRate, isLowShelf: false)
            }
            compressorAttackCoefficient = exp(-1 / (sampleRate * 0.008))
            compressorReleaseCoefficient = exp(-1 / (sampleRate * 0.12))
            compressorThresholdAmplitude = pow(10, options.compressorThreshold / 20)
            limiterCeilingAmplitude = pow(10, options.limiterCeiling / 20)
            alignmentSamples = Array(repeating: 0, count: channels)
            if channels > 0 {
                alignmentSamples[0] = min(alignmentBuffers[0].count - 1, Int((options.leftDelayMilliseconds * sampleRate / 1000).rounded()))
            }
            if channels > 1 {
                alignmentSamples[1] = min(alignmentBuffers[1].count - 1, Int((options.rightDelayMilliseconds * sampleRate / 1000).rounded()))
            }
            if processingWord != lastProcessing {
                for channel in alignmentBuffers.indices {
                    alignmentBuffers[channel] = Array(repeating: 0, count: alignmentBuffers[channel].count)
                    alignmentPositions[channel] = 0
                }
            }
            carFader = position.fader
            carBalance = position.balance
            lastWords = currentWords
            lastMixWords = mixWords
            lastQ = q
            lastProcessing = processingWord
            lastMixProcessing = mixProcessingWord
            lastMixActive = mixIsActive
            lastCarPosition = carPosition
        }

        if speakersChanged || lastVirtualSpeakers.count != 6 {
            for index in 0..<6 {
                let speaker = virtualConfigurations[index]
                virtualHPFilters[index].configureHighPass(frequency: speaker.highPassFrequency, sampleRate: sampleRate)
                virtualLPFilters[index].configureLowPass(frequency: speaker.lowPassFrequency, sampleRate: sampleRate)
                virtualPEQFilters[index][0].configure(frequency: 120, gain: speaker.lowGain, sampleRate: sampleRate, q: 0.7)
                virtualPEQFilters[index][1].configure(frequency: 1_000, gain: speaker.midGain, sampleRate: sampleRate, q: 0.7)
                virtualPEQFilters[index][2].configure(frequency: 8_000, gain: speaker.highGain, sampleRate: sampleRate, q: 0.7)
                virtualDelaySamples[index] = min(virtualDelayBuffers[index].count - 1, Int((speaker.delayMilliseconds * sampleRate / 1000).rounded()))
                virtualLimiterCeilings[index] = pow(10, speaker.limiterCeiling / 20)
                virtualGainAmplitudes[index] = pow(10, speaker.gain / 20)
                virtualDelayBuffers[index] = Array(repeating: 0, count: virtualDelayBuffers[index].count)
                virtualDelayPositions[index] = 0
            }
            lastVirtualSpeakers = virtualConfigurations
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        if isNonInterleaved {
            for channel in 0..<min(channels, buffers.count) {
                guard let data = buffers[channel].mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                for frame in 0..<min(frames, Int(buffers[channel].mDataByteSize) / MemoryLayout<Float>.size) {
                    samples[frame] = processSample(samples[frame], channel: channel, options: options)
                }
            }
        } else if let data = buffers.first?.mData {
            let samples = data.assumingMemoryBound(to: Float.self)
            let sampleCount = min(frames * channels, Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size)
            for sample in 0..<sampleCount {
                let channel = sample % channels
                samples[sample] = processSample(samples[sample], channel: channel, options: options)
            }
        }
    }

    private func processSample(_ sample: Float, channel: Int, options: BreeEQProcessingOptions) -> Float {
        var value = sample
        if options.highPassEnabled { value = highPassFilters[channel].process(value) }
        if options.lowShelfEnabled { value = lowShelfFilters[channel].process(value) }
        for band in activeGraphicBands where filters[channel].indices.contains(band) {
            value = filters[channel][band].process(value)
        }
        if options.highShelfEnabled { value = highShelfFilters[channel].process(value) }
        if options.lowPassEnabled { value = lowPassFilters[channel].process(value) }

        if options.compressorEnabled {
            let magnitude = abs(value)
            let coefficient = magnitude > compressorEnvelope[channel]
                ? compressorAttackCoefficient
                : compressorReleaseCoefficient
            compressorEnvelope[channel] = coefficient * compressorEnvelope[channel] + (1 - coefficient) * magnitude
            if compressorEnvelope[channel] > compressorThresholdAmplitude {
                let compressed = compressorThresholdAmplitude + (compressorEnvelope[channel] - compressorThresholdAmplitude) / options.compressorRatio
                value *= compressed / max(compressorEnvelope[channel], 0.00001)
            }
        }
        if options.loudnessCompensationEnabled {
            let magnitude = abs(value)
            let coefficient: Float = magnitude > loudnessEnvelope[channel] ? 0.985 : 0.999
            loudnessEnvelope[channel] = coefficient * loudnessEnvelope[channel] + (1 - coefficient) * magnitude
            let quiet = min(1, max(0, (0.18 - loudnessEnvelope[channel]) / 0.18))
            value *= 1 + quiet * 0.35
        }

        if channels >= 2 {
            let opposite = channel.isMultiple(of: 2) ? channel + 1 : channel - 1
            if opposite < stereoHistory.count {
                if carFader < 0 {
                    let rearBlend = -carFader * 0.22
                    value = value * (1 - rearBlend) + stereoHistory[opposite] * rearBlend
                } else if carFader > 0 {
                    value += (value - stereoHistory[opposite]) * carFader * 0.18
                }
            }
        }
        if channel.isMultiple(of: 2) {
            value *= carBalance > 0 ? 1 - carBalance : 1
            if options.invertLeftPolarity { value = -value }
        } else {
            value *= carBalance < 0 ? 1 + carBalance : 1
            if options.invertRightPolarity { value = -value }
        }
        stereoHistory[channel] = value

        if alignmentSamples.indices.contains(channel), alignmentSamples[channel] > 0 {
            let delay = alignmentSamples[channel]
            let position = alignmentPositions[channel]
            let read = (position - delay + alignmentBuffers[channel].count) % alignmentBuffers[channel].count
            let delayedValue = alignmentBuffers[channel][read]
            alignmentBuffers[channel][position] = value
            alignmentPositions[channel] = (position + 1) % alignmentBuffers[channel].count
            value = delayedValue
        } else if alignmentBuffers.indices.contains(channel) {
            alignmentBuffers[channel][alignmentPositions[channel]] = value
            alignmentPositions[channel] = (alignmentPositions[channel] + 1) % alignmentBuffers[channel].count
        }
        if options.limiterEnabled {
            value = min(limiterCeilingAmplitude, max(-limiterCeilingAmplitude, value))
        }
        value = processVirtualSpeakers(value, sourceChannel: channel)
        if options.limiterEnabled {
            value = min(limiterCeilingAmplitude, max(-limiterCeilingAmplitude, value))
        }
        return value.isFinite ? value : sample
    }

    private func processVirtualSpeakers(_ input: Float, sourceChannel: Int) -> Float {
        guard virtualHPFilters.count == 6 else { return input }
        let side = sourceChannel.isMultiple(of: 2) ? Self.leftVirtualSpeakerIndices : Self.rightVirtualSpeakerIndices
        // Avoid turning a disabled DSP side into digital silence if its three
        // virtual channels are all switched off.
        guard side.contains(where: { virtualConfigurations[$0].enabled }) else { return input }
        var mixed: Float = 0
        for (position, index) in side.enumerated() {
            let speaker = virtualConfigurations[index]
            guard speaker.enabled else { continue }
            var value = input
            if speaker.highPassEnabled { value = virtualHPFilters[index].process(value) }
            if speaker.lowGain != 0 { value = virtualPEQFilters[index][0].process(value) }
            if speaker.midGain != 0 { value = virtualPEQFilters[index][1].process(value) }
            if speaker.highGain != 0 { value = virtualPEQFilters[index][2].process(value) }
            if speaker.lowPassEnabled { value = virtualLPFilters[index].process(value) }
            value *= virtualGainAmplitudes[index]
            if speaker.inverted { value = -value }
            if virtualDelaySamples[index] > 0 {
                let delay = virtualDelaySamples[index]
                let cursor = virtualDelayPositions[index]
                let read = (cursor - delay + virtualDelayBuffers[index].count) % virtualDelayBuffers[index].count
                let delayed = virtualDelayBuffers[index][read]
                virtualDelayBuffers[index][cursor] = value
                virtualDelayPositions[index] = (cursor + 1) % virtualDelayBuffers[index].count
                value = delayed
            } else {
                let cursor = virtualDelayPositions[index]
                virtualDelayBuffers[index][cursor] = value
                virtualDelayPositions[index] = (cursor + 1) % virtualDelayBuffers[index].count
            }
            if speaker.limiterEnabled {
                value = min(virtualLimiterCeilings[index], max(-virtualLimiterCeilings[index], value))
            }
            mixed += value * Self.virtualMixWeights[position]
        }
        // The normalized mix preserves unity gain when all six virtual channels are flat.
        return mixed / 1.35
    }
}

private struct EQBiquad {
    private var b0: Float = 1
    private var b1: Float = 0
    private var b2: Float = 0
    private var a1: Float = 0
    private var a2: Float = 0
    private var x1: Float = 0
    private var x2: Float = 0
    private var y1: Float = 0
    private var y2: Float = 0

    mutating func configure(frequency: Float, gain: Float, sampleRate: Float, q: Float = 1) {
        guard sampleRate > 0 else { return }
        let boundedFrequency = min(frequency, sampleRate * 0.45)
        let omega = 2 * Float.pi * boundedFrequency / sampleRate
        let alpha = sin(omega) / (2 * min(4, max(0.3, q)))
        let amplitude = pow(10, gain / 40)
        let cosine = cos(omega)
        let a0 = 1 + alpha / amplitude
        b0 = (1 + alpha * amplitude) / a0
        b1 = (-2 * cosine) / a0
        b2 = (1 - alpha * amplitude) / a0
        a1 = (-2 * cosine) / a0
        a2 = (1 - alpha / amplitude) / a0
    }

    mutating func configureHighPass(frequency: Float, sampleRate: Float) {
        configurePass(frequency: frequency, sampleRate: sampleRate, isHighPass: true)
    }

    mutating func configureLowPass(frequency: Float, sampleRate: Float) {
        configurePass(frequency: frequency, sampleRate: sampleRate, isHighPass: false)
    }

    private mutating func configurePass(frequency: Float, sampleRate: Float, isHighPass: Bool) {
        guard sampleRate > 0 else { return }
        let omega = 2 * Float.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let cosine = cos(omega)
        let alpha = sin(omega) / (2 * 0.7071)
        let a0 = 1 + alpha
        if isHighPass {
            b0 = ((1 + cosine) / 2) / a0
            b1 = (-(1 + cosine)) / a0
            b2 = ((1 + cosine) / 2) / a0
        } else {
            b0 = ((1 - cosine) / 2) / a0
            b1 = (1 - cosine) / a0
            b2 = ((1 - cosine) / 2) / a0
        }
        a1 = (-2 * cosine) / a0
        a2 = (1 - alpha) / a0
        clearHistory()
    }

    mutating func configureShelf(frequency: Float, gain: Float, sampleRate: Float, isLowShelf: Bool) {
        guard sampleRate > 0 else { return }
        let boundedFrequency = min(frequency, sampleRate * 0.45)
        let omega = 2 * Float.pi * boundedFrequency / sampleRate
        let cosine = cos(omega)
        let amplitude = pow(10, gain / 40)
        let alpha = sin(omega) / (2 * 0.7071)
        let beta = 2 * sqrt(amplitude) * alpha
        let a0: Float
        if isLowShelf {
            let b0Raw = amplitude * ((amplitude + 1) - (amplitude - 1) * cosine + beta)
            let b1Raw = 2 * amplitude * ((amplitude - 1) - (amplitude + 1) * cosine)
            let b2Raw = amplitude * ((amplitude + 1) - (amplitude - 1) * cosine - beta)
            a0 = (amplitude + 1) + (amplitude - 1) * cosine + beta
            let a1Raw = -2 * ((amplitude - 1) + (amplitude + 1) * cosine)
            let a2Raw = (amplitude + 1) + (amplitude - 1) * cosine - beta
            b0 = b0Raw / a0; b1 = b1Raw / a0; b2 = b2Raw / a0
            a1 = a1Raw / a0; a2 = a2Raw / a0
        } else {
            let b0Raw = amplitude * ((amplitude + 1) + (amplitude - 1) * cosine + beta)
            let b1Raw = -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosine)
            let b2Raw = amplitude * ((amplitude + 1) + (amplitude - 1) * cosine - beta)
            a0 = (amplitude + 1) - (amplitude - 1) * cosine + beta
            let a1Raw = 2 * ((amplitude - 1) - (amplitude + 1) * cosine)
            let a2Raw = (amplitude + 1) - (amplitude - 1) * cosine - beta
            b0 = b0Raw / a0; b1 = b1Raw / a0; b2 = b2Raw / a0
            a1 = a1Raw / a0; a2 = a2Raw / a0
        }
        clearHistory()
    }

    mutating func process(_ sample: Float) -> Float {
        let output = b0 * sample + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = sample
        y2 = y1
        y1 = output
        return output.isFinite ? output : sample
    }

    mutating func clearHistory() {
        x1 = 0
        x2 = 0
        y1 = 0
        y2 = 0
    }
}
#endif
