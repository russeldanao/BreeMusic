#if os(iOS)
import SwiftUI

struct GraphicEqualizerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var gains = BreeEQSettings.shared.gains
    @State private var isEnabled = BreeEQSettings.shared.enabled
    @State private var parametricQ = BreeEQSettings.shared.parametricQ
    @State private var processing = BreeEQSettings.shared.processingOptions
    @State private var carFader = BreeEQSettings.shared.carFader
    @State private var carBalance = BreeEQSettings.shared.carBalance
    @State private var virtualSpeakers = BreeEQSettings.shared.virtualSpeakers
    @State private var selectedAcousticPreset = "Manual"
    @State private var customPresets = EqualizerPresets.loadCustom()
    @State private var showingSavePreset = false
    @State private var showingRenamePreset = false
    @State private var renamingPresetID: String?
    @State private var renamedPresetName = ""
    @State private var showingBandList = false
    @State private var customPresetName = ""
    @State private var expandedSpeakerID: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 20) {
                Toggle("Equalizer", isOn: $isEnabled)
                    .font(.headline)
                    .onChange(of: isEnabled) { _, _ in saveSettings() }

                EqualizerCurve(gains: gains, frequencies: BreeEQSettings.frequencies)
                    .frame(height: 130)
                    .padding(.horizontal, 8)

                HStack {
                    Text("+12 dB")
                    Spacer()
                    Text("0 dB")
                    Spacer()
                    Text("−12 dB")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

                Button { showingBandList = true } label: {
                    Label("Edit all 31 bands", systemImage: "slider.vertical.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .sheet(isPresented: $showingBandList) {
                    bandListPopup
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackground(.ultraThinMaterial)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Parametric shape")
                        .font(.headline)
                    HStack {
                        Text("Q width")
                        Slider(value: $parametricQ, in: 0.3...4.0, step: 0.1)
                        Text(String(format: "%.1f", parametricQ))
                            .font(.caption.monospacedDigit())
                            .frame(width: 34)
                    }
                    Text("Adjusts the bandwidth of all 31 bell filters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))

                virtualSpeakerControls

                Menu {
                    Section("General") {
                        ForEach(EqualizerPresets.general) { presetButton($0) }
                    }
                    Section("Listening styles") {
                        ForEach(EqualizerPresets.listeningStyles) { presetButton($0) }
                    }
                    Section("Genres") {
                        ForEach(EqualizerPresets.genres) { presetButton($0) }
                    }
                } label: {
                    Label("Choose a preset", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                Button {
                    customPresetName = ""
                    showingSavePreset = true
                } label: {
                    Label("Save full EQ preset", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                if !customPresets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("My presets", systemImage: "bookmark.fill")
                            .font(.headline)
                        ForEach(customPresets) { preset in
                            HStack(spacing: 12) {
                                Button {
                                    apply(preset)
                                } label: {
                                    HStack {
                                        Text(preset.name)
                                        Spacer()
                                        if gains == Self.expandedGains(from: preset.gains) {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.cyan)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Menu {
                                    Button("Rename", systemImage: "pencil") {
                                        renamingPresetID = preset.id
                                        renamedPresetName = preset.name
                                        showingRenamePreset = true
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        customPresets.removeAll { $0.id == preset.id }
                                        EqualizerPresets.saveCustom(customPresets)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.title3)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Actions for \(preset.name)")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Changes apply to BreeMusic playback, including audio routed to your car.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            }
            .navigationTitle("Equalizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset EQ", systemImage: "arrow.counterclockwise") {
                        resetEQGraph()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Save custom preset", isPresented: $showingSavePreset) {
                TextField("Preset name", text: $customPresetName)
                Button("Save") {
                    let name = customPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    let preset = EqualizerPreset(
                        name: name,
                        gains: gains,
                        enabled: isEnabled,
                        parametricQ: parametricQ,
                        processing: processing,
                        carFader: carFader,
                        carBalance: carBalance,
                        virtualSpeakers: virtualSpeakers
                    )
                    customPresets.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                    customPresets.append(preset)
                    EqualizerPresets.saveCustom(customPresets)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Save the 31-band curve and all six virtual speaker channels.")
            }
            .sheet(isPresented: $showingRenamePreset) {
                NavigationStack {
                    Form {
                        TextField("Preset name", text: $renamedPresetName)
                            .textInputAutocapitalization(.words)
                        Text("Renaming keeps the saved EQ and speaker settings unchanged.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .navigationTitle("Rename Preset")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingRenamePreset = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { saveRenamedPreset() }
                                .disabled(!canSaveRenamedPreset)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .onChange(of: parametricQ) { _, _ in saveSettings() }
            .onChange(of: processing) { _, _ in saveSettings() }
            .onChange(of: carFader) { _, _ in saveSettings() }
            .onChange(of: carBalance) { _, _ in saveSettings() }
            .onChange(of: virtualSpeakers) { _, updated in
                if !AcousticPresets.all.contains(where: { $0.matches(updated) }) {
                    selectedAcousticPreset = "Manual"
                }
                saveSettings()
            }
        }
    }

    private var bandListPopup: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(BreeEQSettings.frequencies.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            Text(bandFrequencyLabel(BreeEQSettings.frequencies[index]))
                                .font(.caption.monospacedDigit())
                                .frame(width: 58, alignment: .trailing)
                            Slider(value: Binding(
                                get: { gains[index] },
                                set: { newValue in
                                    gains[index] = newValue
                                    if newValue != 0 { isEnabled = true }
                                    saveSettings()
                                }
                            ), in: -12...12, step: 1)
                            .tint(BreeHomePalette.lightOrange)
                            Text(String(format: "%+g", gains[index]))
                                .font(.caption.monospacedDigit())
                                .frame(width: 38, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("31-Band Equalizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingBandList = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func bandFrequencyLabel(_ frequency: Float) -> String {
        frequency >= 1_000 ? String(format: "%g kHz", frequency / 1_000) : String(format: "%g Hz", frequency)
    }

    private var virtualSpeakerControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Virtual 6-channel DSP", systemImage: "hifispeaker.2")
                    .font(.headline)
                Spacer()
                Menu {
                    ForEach(AcousticPresets.all, id: \.name) { preset in
                        Button(preset.name) {
                            virtualSpeakers = preset.apply(to: virtualSpeakers)
                            selectedAcousticPreset = preset.name
                            saveSettings()
                        }
                    }
                } label: {
                    Label(selectedAcousticPreset, systemImage: "waveform")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                }
            }

            Text("Open one speaker at a time. Adjustments shape BreeMusic’s stereo output; your head unit still controls the car’s physical speaker routing.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Text("QUICK TONE PROFILES")
                    .font(.caption.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset DSP", systemImage: "arrow.counterclockwise") {
                    resetVirtualDSP()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.glass)
            }

            ForEach(virtualSpeakers.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        withAnimation(.smooth(duration: 0.24)) {
                            expandedSpeakerID = expandedSpeakerID == index ? nil : index
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: index >= 4 ? "speaker.wave.2" : "hifispeaker")
                                .font(.title3)
                                .foregroundStyle(BreeHomePalette.lightOrange)
                                .frame(width: 44, height: 44)
                                .background(.thinMaterial, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(virtualSpeakers[index].name)
                                    .font(.body.weight(.semibold))
                            }
                            Spacer(minLength: 4)
                            Image(systemName: expandedSpeakerID == index ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if expandedSpeakerID == index {
                        Divider()
                        speakerEditor(index: index)
                            .transition(.opacity)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08)))
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func speakerEditor(index: Int) -> some View {
        let speaker = Binding(get: { virtualSpeakers[index] }, set: { virtualSpeakers[index] = $0 })
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer()
                Button("Reset speaker", systemImage: "arrow.counterclockwise") {
                    resetSpeaker(index)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.glass)
            }

            speakerControlGroup("CHANNEL") {
                Toggle("Channel enabled", isOn: speaker.enabled)
                speakerSlider("Output level", value: speaker.gain, range: -12...12, suffix: "dB")
            }

            speakerControlGroup("CROSSOVER") {
                Toggle("High-pass filter", isOn: speaker.highPassEnabled)
                if speaker.wrappedValue.highPassEnabled {
                    speakerFrequencySlider("Cut low frequencies", value: speaker.highPassFrequency, range: 20...4_000)
                }
                Toggle("Low-pass filter", isOn: speaker.lowPassEnabled)
                if speaker.wrappedValue.lowPassEnabled {
                    speakerFrequencySlider("Cut high frequencies", value: speaker.lowPassFrequency, range: 1_000...20_000)
                }
            }

            speakerControlGroup("TONE & TIMING") {
                speakerSlider("Time alignment", value: speaker.delayMilliseconds, range: 0...20, suffix: "ms")
                speakerSlider("Bass · 120 Hz", value: speaker.lowGain, range: -12...12, suffix: "dB")
                speakerSlider("Midrange · 1 kHz", value: speaker.midGain, range: -12...12, suffix: "dB")
                speakerSlider("Treble · 8 kHz", value: speaker.highGain, range: -12...12, suffix: "dB")
            }

            speakerControlGroup("PROTECTION") {
                Toggle("Invert polarity", isOn: speaker.inverted)
                Toggle("Channel limiter", isOn: speaker.limiterEnabled)
                if speaker.wrappedValue.limiterEnabled {
                    speakerSlider("Limiter ceiling", value: speaker.limiterCeiling, range: -12...0, suffix: "dB")
                }
            }
        }
        .font(.body)
    }

    private func speakerControlGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(1)
                .italic()
                .foregroundStyle(BreeHomePalette.lightOrange)
                .frame(maxWidth: .infinity, alignment: .center)
            content()
        }
    }

    private func speakerSlider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>, suffix: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(suffix == "ms" ? String(format: "%.1f ms", value.wrappedValue) : decibelLabel(value.wrappedValue))
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.5)
                .tint(BreeHomePalette.lightOrange)
                .controlSize(.large)
        }
    }

    private func speakerFrequencySlider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: "%.1f Hz", value.wrappedValue))
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.5)
                .tint(BreeHomePalette.lightOrange)
                .controlSize(.large)
        }
    }

    private func decibelLabel(_ value: Float) -> String {
        if abs(value) < 0.05 { return "0.0 dB" }
        return String(format: "%+.1f dB", value)
    }

    private var advancedProcessingControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Crossovers & dynamics")
                    .font(.headline)
                Spacer()
                Button("Car starter") {
                    // A stereo stream cannot split a dedicated subwoofer feed.
                    // This applies the useful main-speaker HPF and output limiter only.
                    processing.highPassEnabled = true
                    processing.highPassFrequency = 80
                    processing.limiterEnabled = true
                    processing.limiterCeiling = -1
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.glass)
            }
            Text("Car starter sets an 80 Hz high-pass and a −1 dB peak ceiling on BreeMusic’s stereo output. Use your car’s DSP for a separate subwoofer low-pass or per-speaker tuning.")
                .font(.caption)
                .foregroundStyle(.secondary)
            filterControl(title: "High-pass", isOn: $processing.highPassEnabled, value: $processing.highPassFrequency, range: [20, 30, 40, 50, 60, 80, 100, 120, 150, 200, 300, 400, 600, 800], suffix: "Hz")
            filterControl(title: "Low-pass", isOn: $processing.lowPassEnabled, value: $processing.lowPassFrequency, range: [2_000, 3_000, 4_000, 5_000, 6_000, 7_000, 8_000, 9_000, 10_000, 11_000, 12_000, 14_000, 16_000, 18_000, 20_000], suffix: "Hz")
            filterControl(title: "Low shelf", isOn: $processing.lowShelfEnabled, value: $processing.lowShelfGain, range: Array(stride(from: Float(-12), through: 12, by: 1)), suffix: "dB")
            filterControl(title: "High shelf", isOn: $processing.highShelfEnabled, value: $processing.highShelfGain, range: Array(stride(from: Float(-12), through: 12, by: 1)), suffix: "dB")
            filterControl(title: "Dynamic compression", isOn: $processing.compressorEnabled, value: $processing.compressorThreshold, range: Array(stride(from: Float(-60), through: 0, by: 1)), suffix: "dB")
            if processing.compressorEnabled {
                HStack {
                    Text("Ratio")
                    Slider(value: $processing.compressorRatio, in: 1...20, step: 1)
                    Text(String(format: "%.0f:1", processing.compressorRatio))
                        .font(.caption.monospacedDigit())
                        .frame(width: 42)
                }
            }
            filterControl(title: "Limiter", isOn: $processing.limiterEnabled, value: $processing.limiterCeiling, range: Array(stride(from: Float(-12), through: 0, by: 1)), suffix: "dB")
            Toggle("Loudness compensation", isOn: $processing.loudnessCompensationEnabled)
            Divider()
            Text("Time alignment")
                .font(.subheadline.weight(.semibold))
            alignmentControl(title: "Left channel", value: $processing.leftDelayMilliseconds)
            alignmentControl(title: "Right channel", value: $processing.rightDelayMilliseconds)
            Text("Add up to 20 ms of delay per channel to help center the stereo image from your listening position.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text("Phase & polarity")
                .font(.subheadline.weight(.semibold))
            Toggle("Invert left polarity", isOn: $processing.invertLeftPolarity)
            Toggle("Invert right polarity", isOn: $processing.invertRightPolarity)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private var carSpeakerControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Car speaker DSP", systemImage: "car.side.rear.open")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    carFader = 0
                    carBalance = 0
                }
                .font(.caption.weight(.semibold))
            }

            CarSpeakerMap(fader: carFader, balance: carBalance)
                .frame(height: 142)

            carPositionSlider(title: "Front / rear focus", leading: "Rear", trailing: "Front", value: $carFader)
            carPositionSlider(title: "Balance", leading: "Left", trailing: "Right", value: $carBalance)

            Text("Balance and stereo focus are processed in BreeMusic. CarPlay sends stereo audio to the car, so true front/rear speaker fader and per-speaker routing still need to be set in your car’s audio system.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func carPositionSlider(title: String, leading: String, trailing: String, value: Binding<Float>) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%+.0f", value.wrappedValue * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text(leading).font(.caption2).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                Slider(value: value, in: -1...1, step: 0.01)
                    .tint(BreeHomePalette.lightOrange)
                Text(trailing).font(.caption2).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
            }
        }
    }

    private func alignmentControl(title: String, value: Binding<Float>) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.1f ms", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...20, step: 0.1)
        }
    }

    private func filterControl(title: String, isOn: Binding<Bool>, value: Binding<Float>, range: [Float], suffix: String) -> some View {
        VStack(spacing: 4) {
            Toggle(title, isOn: isOn)
            if isOn.wrappedValue {
                HStack {
                    Slider(value: value, in: range.first!...range.last!, step: range.count > 1 ? range[1] - range[0] : 1)
                    Text(String(format: suffix == "Hz" ? "%.0f Hz" : "%+.0f dB", value.wrappedValue))
                        .font(.caption.monospacedDigit())
                        .frame(width: 66, alignment: .trailing)
                }
            }
        }
    }

    private func presetButton(_ preset: EqualizerPreset) -> some View {
        Button(preset.name) {
            apply(preset)
        }
    }

    private func apply(_ preset: EqualizerPreset) {
        gains = Self.expandedGains(from: preset.gains)
        isEnabled = preset.enabled ?? (preset.name != "Flat")
        if let presetQ = preset.parametricQ { parametricQ = presetQ }
        if let presetProcessing = preset.processing { processing = presetProcessing }
        if let presetFader = preset.carFader { carFader = presetFader }
        if let presetBalance = preset.carBalance { carBalance = presetBalance }
        if let presetSpeakers = preset.virtualSpeakers, presetSpeakers.count == 6 {
            virtualSpeakers = presetSpeakers
            selectedAcousticPreset = AcousticPresets.all.first(where: { $0.matches(presetSpeakers) })?.name ?? "Manual"
            expandedSpeakerID = nil
        }
        saveSettings()
    }

    private static func expandedGains(from source: [Float]) -> [Float] {
        if source.count == BreeEQSettings.frequencies.count { return source }
        let sourceFrequencies: [Float] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
        return BreeEQSettings.frequencies.map { frequency in
            guard let upperIndex = sourceFrequencies.firstIndex(where: { $0 >= frequency }) else {
                return source.last ?? 0
            }
            guard upperIndex > 0 else { return source.first ?? 0 }
            let lowerIndex = upperIndex - 1
            let lowerLog = log2(sourceFrequencies[lowerIndex])
            let upperLog = log2(sourceFrequencies[upperIndex])
            let progress = (log2(frequency) - lowerLog) / (upperLog - lowerLog)
            return source[lowerIndex] + (source[upperIndex] - source[lowerIndex]) * progress
        }
    }

    private func saveSettings() {
        BreeEQSettings.shared.update(
            enabled: isEnabled,
            gains: gains,
            parametricQ: parametricQ,
            processingOptions: processing,
            carFader: carFader,
            carBalance: carBalance,
            virtualSpeakers: virtualSpeakers
        )
    }

    private var canSaveRenamedPreset: Bool {
        let candidate = renamedPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, let renamingPresetID else { return false }
        return !customPresets.contains {
            $0.id != renamingPresetID && $0.name.caseInsensitiveCompare(candidate) == .orderedSame
        }
    }

    private func saveRenamedPreset() {
        guard canSaveRenamedPreset,
              let renamingPresetID,
              let index = customPresets.firstIndex(where: { $0.id == renamingPresetID }) else { return }
        customPresets[index].name = renamedPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        EqualizerPresets.saveCustom(customPresets)
        showingRenamePreset = false
    }

    private func resetEQGraph() {
        gains = Array(repeating: 0, count: BreeEQSettings.frequencies.count)
        isEnabled = false
        parametricQ = 1
        saveSettings()
    }

    private func resetVirtualDSP() {
        virtualSpeakers = BreeVirtualSpeaker.defaults
        selectedAcousticPreset = "Manual"
        withAnimation(.smooth(duration: 0.24)) {
            expandedSpeakerID = nil
        }
        saveSettings()
    }

    private func resetSpeaker(_ index: Int) {
        guard virtualSpeakers.indices.contains(index) else { return }
        virtualSpeakers[index] = BreeVirtualSpeaker.defaults[index]
        selectedAcousticPreset = "Manual"
        saveSettings()
    }
}

private struct CarSpeakerMap: View {
    let fader: Float
    let balance: Float

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, 230.0)
            let height = min(geometry.size.height, 142.0)
            let center = CGPoint(
                x: geometry.size.width / 2 + CGFloat(balance) * width * 0.31,
                y: geometry.size.height / 2 - CGFloat(fader) * height * 0.30
            )
            ZStack {
                RoundedRectangle(cornerRadius: 38)
                    .stroke(.white.opacity(0.24), lineWidth: 1.5)
                    .frame(width: width * 0.55, height: height * 0.92)
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.035))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1))
                    .frame(width: width * 0.36, height: height * 0.42)
                VStack {
                    Text("FRONT").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    Spacer()
                    Text("REAR").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                }
                .frame(height: height * 0.78)
                HStack {
                    speakerDot
                    Spacer()
                    speakerDot
                }
                .frame(width: width * 0.46, height: height * 0.72)
                Circle()
                    .fill(Color(red: 0.93, green: 0.39, blue: 0.14))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
                    .shadow(color: .orange.opacity(0.38), radius: 8)
                    .position(center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speaker focus map")
            .accessibilityValue("\(fader < 0 ? "Rear" : "Front") \(Int(abs(fader * 100))) percent, balance \(balance < 0 ? "left" : "right") \(Int(abs(balance * 100))) percent")
        }
    }

    private var speakerDot: some View {
        VStack {
            Circle().fill(.white.opacity(0.42)).frame(width: 10, height: 10)
            Spacer()
            Circle().fill(.white.opacity(0.42)).frame(width: 10, height: 10)
        }
        .frame(height: 64)
    }
}

private struct EqualizerPreset: Identifiable, Codable {
    var name: String
    let gains: [Float]
    var enabled: Bool? = nil
    var parametricQ: Float? = nil
    var processing: BreeEQProcessingOptions? = nil
    var carFader: Float? = nil
    var carBalance: Float? = nil
    var virtualSpeakers: [BreeVirtualSpeaker]? = nil
    var id: String { name }
}

private struct AcousticPreset {
    let name: String
    let low: Float
    let mid: Float
    let high: Float

    func apply(to speakers: [BreeVirtualSpeaker]) -> [BreeVirtualSpeaker] {
        speakers.map { source in
            var speaker = source
            speaker.lowGain = low
            speaker.midGain = mid
            speaker.highGain = high
            return speaker
        }
    }

    func matches(_ speakers: [BreeVirtualSpeaker]) -> Bool {
        speakers.allSatisfy { $0.lowGain == low && $0.midGain == mid && $0.highGain == high }
    }
}

private enum AcousticPresets {
    // Original BreeMusic tonal starting points, editable per virtual speaker.
    static let all: [AcousticPreset] = [
        AcousticPreset(name: "Bree Lively", low: 3, mid: 1, high: 2),
        AcousticPreset(name: "Bree Signature", low: 0, mid: 1, high: 0),
        AcousticPreset(name: "Bree Powerful", low: 5, mid: 1, high: 1),
        AcousticPreset(name: "Bree Relaxing", low: 1, mid: 0, high: -3)
    ]
}

private enum EqualizerPresets {
    static func loadCustom() -> [EqualizerPreset] {
        guard let data = UserDefaults.standard.data(forKey: "breeEQCustomPresets"),
              let presets = try? JSONDecoder().decode([EqualizerPreset].self, from: data) else { return [] }
        return presets
    }

    static func saveCustom(_ presets: [EqualizerPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: "breeEQCustomPresets")
    }

    static let general = [
        EqualizerPreset(name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EqualizerPreset(name: "Bass Boost", gains: [-2, 4, 6, 4, 1, 0, 0, 0, 0, 0]),
        EqualizerPreset(name: "Bass Reducer", gains: [-5, -4, -3, -1, 0, 0, 0, 0, 0, 0]),
        EqualizerPreset(name: "Treble Boost", gains: [0, 0, 0, -1, 0, 1, 3, 5, 5, 3]),
        EqualizerPreset(name: "Treble Reducer", gains: [0, 0, 0, 0, 0, -1, -2, -3, -4, -4]),
        EqualizerPreset(name: "V Shape", gains: [4, 3, 1, -2, -3, -2, 0, 2, 4, 4]),
    ]

    static let listeningStyles = [
        EqualizerPreset(name: "Acoustic", gains: [2, 2, 1, 1, 0, 1, 2, 3, 3, 2]),
        EqualizerPreset(name: "Classical", gains: [3, 2, 1, 0, -1, -1, 0, 2, 3, 4]),
        EqualizerPreset(name: "Headphones", gains: [3, 2, 0, -1, -1, 0, 1, 2, 3, 4]),
        EqualizerPreset(name: "Loudness", gains: [4, 3, 1, 0, -1, 0, 2, 3, 4, 3]),
        EqualizerPreset(name: "Small Speakers", gains: [-5, -4, -2, 0, 2, 3, 3, 2, 1, 0]),
        EqualizerPreset(name: "Spoken Word", gains: [-2, -1, 0, 2, 3, 3, 2, 1, 0, -1]),
        EqualizerPreset(name: "Vocal", gains: [-2, -1, 0, 2, 4, 4, 2, 0, -1, -2]),
    ]

    static let genres = [
        EqualizerPreset(name: "Dance", gains: [4, 5, 3, 0, -1, 2, 3, 4, 5, 4]),
        EqualizerPreset(name: "Electronic", gains: [3, 4, 2, 0, -2, 1, 2, 3, 4, 3]),
        EqualizerPreset(name: "Hip-Hop", gains: [5, 4, 1, -2, -1, 2, 0, 1, 3, 4]),
        EqualizerPreset(name: "Jazz", gains: [3, 2, 1, 2, -1, -1, 0, 1, 3, 4]),
        EqualizerPreset(name: "Latin", gains: [3, 2, 0, 1, -1, 1, 2, 3, 3, 2]),
        EqualizerPreset(name: "Lounge", gains: [-1, 1, 2, 1, 0, 1, 2, 2, 1, 0]),
        EqualizerPreset(name: "Piano", gains: [2, 1, 0, 2, 3, 1, 0, 1, 3, 4]),
        EqualizerPreset(name: "Pop", gains: [-1, 2, 4, 4, 1, -1, -1, 0, 1, 1]),
        EqualizerPreset(name: "R&B", gains: [3, 2, 0, -2, -1, 1, 2, 3, 3, 2]),
        EqualizerPreset(name: "Rock", gains: [4, 3, -1, -3, -1, 2, 4, 5, 5, 4]),
    ]
}

private struct EqualizerCurve: View {
    let gains: [Float]
    let frequencies: [Float]

    var body: some View {
        Canvas { context, size in
            for level in [-12.0, -6.0, 0.0, 6.0, 12.0] {
                let y = size.height * CGFloat((12 - level) / 24)
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    grid,
                    with: .color(level == 0 ? .secondary.opacity(0.6) : .secondary.opacity(0.22)),
                    style: StrokeStyle(lineWidth: 1, dash: level == 0 ? [] : [3, 4])
                )
            }

            guard gains.count > 1 else { return }
            var curve = Path()
            for (index, gain) in gains.enumerated() {
                let minLog = log2(frequencies.first ?? 20)
                let maxLog = log2(frequencies.last ?? 20_000)
                let normalizedFrequency = (log2(frequencies[index]) - minLog) / (maxLog - minLog)
                let x = size.width * CGFloat(normalizedFrequency)
                let boundedGain = min(12, max(-12, gain))
                let y = size.height * CGFloat((12 - boundedGain) / 24)
                let point = CGPoint(x: x, y: y)
                if index == 0 {
                    curve.move(to: point)
                } else {
                    curve.addLine(to: point)
                }
                context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(Color.accentColor))
            }
            context.stroke(curve, with: .color(Color.accentColor), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .accessibilityLabel("Equalizer curve")
    }
}

private struct EqualizerBandControl: View {
    let frequency: Float
    @Binding var gain: Float

    private var frequencyLabel: String {
        frequency >= 1_000 ? "\(Int(frequency / 1_000))k" : "\(Int(frequency))"
    }

    var body: some View {
        VStack(spacing: 7) {
            Text(String(format: "%+.0f", gain))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34)

            GeometryReader { geometry in
                let height = geometry.size.height
                let progress = CGFloat((gain + 12) / 24)
                let knobY = height * (1 - progress)
                ZStack {
                    Capsule()
                        .fill(.secondary.opacity(0.18))
                        .frame(width: 4)
                        .frame(maxWidth: .infinity)
                    Rectangle()
                        .fill(.secondary.opacity(0.65))
                        .frame(width: 22, height: 1)
                        .position(x: geometry.size.width / 2, y: height / 2)
                    Capsule()
                        .fill(.tint)
                        .frame(width: 4, height: max(1, height * abs(progress - 0.5)))
                        .position(
                            x: geometry.size.width / 2,
                            y: (knobY + height / 2) / 2
                        )
                    Circle()
                        .fill(.tint)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                        .position(x: geometry.size.width / 2, y: knobY)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = min(1, max(0, 1 - value.location.y / height))
                            gain = Float((fraction * 24 - 12).rounded())
                        }
                )
            }
            .frame(width: 32, height: 145)
            .accessibilityElement()
            .accessibilityLabel("\(frequencyLabel) hertz band")
            .accessibilityValue("\(gain.formatted()) decibels")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: gain = min(12, gain + 1)
                case .decrement: gain = max(-12, gain - 1)
                @unknown default: break
                }
            }

            Text(frequencyLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34)
        }
        .frame(width: 36)
    }
}
#endif
