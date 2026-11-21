import SwiftUI

/// The harp: chord pads under the left hand, the strum plate on the right, and the
/// instrument, key and effects along the top. The instrument, its sound, the effects
/// and the key are remembered between launches.
struct ContentView: View {
    @StateObject private var player = HarpPlayer()
    private var store: InstrumentStore { player.store }
    @State private var showPicker = false
    @State private var showBuiltInSounds = false
    @State private var showPluginEditor = false
    @State private var showCredits = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    AutoStrumBar(player: player)
                    PadsView(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                VStack(spacing: 10) {
                    PlateControls(player: player)
                    StrumPlateView(player: player)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 300)
            }
            .padding(20)
        }
        .background(Color(white: 0.08).ignoresSafeArea())
        .sheet(isPresented: $showPicker) {
            PluginPickerView(
                selectedPlugin: Binding(get: { store.plugin }, set: { store.choose($0) }),
                builtInSound: store.builtInSound
            )
        }
        .sheet(isPresented: $showBuiltInSounds) {
            BuiltInSoundSheet(title: "Built-in Sound", current: store.builtInSound) { sound in
                store.setBuiltInSound(sound)
                // Play the new sound at once, so it can be heard.
                store.noteOn(60)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.noteOff(60) }
            }
        }
        // Full screen, as in FWD Sequencer: a plugin's own window needs the room, and in
        // a sheet it came up at a much smaller scale (Graham, 2026-11-20).
        .fullScreenCover(isPresented: $showPluginEditor) {
            PluginEditorView(trackID: InstrumentStore.partID,
                             trackName: store.instrumentName,
                             onCommitState: { store.captureInstrumentState() },
                             onReload: { store.reload() })
        }
        .sheet(isPresented: $showCredits) { CreditsView() }
        // BLOCKING while the instrument loads: interrupting a fragile AUv3 while it
        // instantiates crashes it (FWD lesson 1). Do not add .allowsHitTesting(false).
        .overlay {
            if store.isLoading {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large).tint(.white)
                        Text("Loading instruments…")
                            .font(.title3.bold()).foregroundStyle(.white)
                        if let name = store.loadingName {
                            Text(name).font(.callout).foregroundStyle(.white)
                        }
                        Text("Some plugins take a while. The screen unlocks when they're ready.")
                            .font(.footnote).foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(36)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
                .contentShape(Rectangle())
                .transition(.opacity)
            }
        }
        // A safe moment to keep the instrument's sound and save (FWD lesson 3).
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                player.setAutoStrumming(false)
                player.releaseAll()
                store.captureAndSave()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.isLoading)
        .alert("FWD Harp", isPresented: Binding(
            get: { store.notice != nil },
            set: { if !$0 { store.notice = nil } }
        )) {
            Button("OK") { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("FWD Harp")
                .font(.headline)
                .foregroundStyle(Color(white: 0.87))
            StudioToggleChip(title: "HOLD",
                             isOn: Binding(get: { player.selection.isHolding },
                                           set: { player.setHolding($0) }),
                             tint: .orange,
                             accessibilityLabel: "Hold: keep the last chord after lifting your hand")
            RangeChips(player: player)
            ScaleMenu(player: player)
            Spacer()
            keyMenu
            Button { showPicker = true } label: {
                HStack(spacing: 8) {
                    if let plugin = store.plugin {
                        PluginIcon(plugin: plugin, size: 24)
                    } else {
                        Image(systemName: "pianokeys")
                    }
                    Text(store.instrumentName).lineLimit(1)
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color(white: 0.87))
                .studioWindow()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Instrument: \(store.instrumentName)")
            .accessibilityHint("Choose another instrument")

            StudioTapButton(title: "EDIT") {
                if store.plugin == nil { showBuiltInSounds = true } else { showPluginEditor = true }
            }

            EffectsToggleButton(store: store)
                .accessibilityLabel("Edit Instrument")

            Button { showCredits = true } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(Color(white: 0.7))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About and Credits")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// The key the pads play in.
    private var keyMenu: some View {
        Menu {
            ForEach(MajorKey.all, id: \.tonic) { key in
                Button {
                    player.setKey(key)
                } label: {
                    if key == player.key { Label(key.name, systemImage: "checkmark") } else { Text(key.name) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("KEY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(StudioStyle.scaleText)
                Text(player.key.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioStyle.displayText)
            }
            .studioWindow()
        }
        .accessibilityLabel("Key: \(player.key.name) major")
    }
}

/// The plate's range, beside Hold: more octaves, more strings in the same height.
private struct RangeChips: View {
    @ObservedObject var player: HarpPlayer

    var body: some View {
        HStack(spacing: 6) {
            Text("RANGE")
                .font(.system(size: 11, weight: .bold)).tracking(0.8)
                .foregroundStyle(StudioStyle.scaleText)
            ForEach(Array(StrumPlate.octaveRange), id: \.self) { octaves in
                StudioChipLabel(title: "\(octaves)", tint: StudioStyle.displayText,
                                look: player.plateOctaves == octaves ? .on : .off)
                    .onTapGesture { player.setPlateOctaves(octaves) }
                    .accessibilityElement()
                    .accessibilityAddTraits(player.plateOctaves == octaves ? [.isButton, .isSelected] : .isButton)
                    .accessibilityLabel("Range \(octaves) octaves")
            }
        }
    }
}

/// What the plate plays, after RANGE: the chord held, or a scale in the key.
private struct ScaleMenu: View {
    @ObservedObject var player: HarpPlayer

    var body: some View {
        Menu {
            ForEach(PlateScale.allCases, id: \.self) { scale in
                Button {
                    player.setPlateScale(scale)
                } label: {
                    if scale == player.plateScale {
                        Label(scale.title, systemImage: "checkmark")
                    } else {
                        Text(scale.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("SCALE")
                    .font(.system(size: 11, weight: .bold)).tracking(0.8)
                    .foregroundStyle(StudioStyle.scaleText)
                Text(player.plateScale.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(StudioStyle.displayText)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(StudioStyle.scaleText)
            }
            .studioWindow()
        }
        .accessibilityLabel("Plate scale: \(player.plateScale.title)")
    }
}

/// Above the plate: the order of its notes, and the octave buttons that move it.
private struct PlateControls: View {
    @ObservedObject var player: HarpPlayer

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(PlatePattern.allCases, id: \.self) { pattern in
                    Button {
                        player.setPlatePattern(pattern)
                    } label: {
                        if pattern == player.platePattern {
                            Label(pattern.title, systemImage: "checkmark")
                        } else {
                            Text(pattern.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(player.platePattern.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(StudioStyle.displayText)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(StudioStyle.scaleText)
                }
                .studioWindow()
            }
            .accessibilityLabel("Plate order: \(player.platePattern.title)")
            Spacer(minLength: 0)
            Text("OCT")
                .font(.system(size: 11, weight: .bold)).tracking(0.8)
                .foregroundStyle(StudioStyle.scaleText)
            octaveButton("chevron.down", step: -1, label: "Octave down",
                         enabled: player.octaveShift > StrumPlate.octaveShiftRange.lowerBound)
            Text(player.octaveShift > 0 ? "+\(player.octaveShift)" : "\(player.octaveShift)")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioStyle.displayText)
                .frame(minWidth: 22)
                .accessibilityLabel("Octave \(player.octaveShift)")
            octaveButton("chevron.up", step: 1, label: "Octave up",
                         enabled: player.octaveShift < StrumPlate.octaveShiftRange.upperBound)
            Spacer(minLength: 0)
        }
    }

    private func octaveButton(_ symbol: String, step: Int, label: String, enabled: Bool) -> some View {
        Button { player.shiftOctave(by: step) } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? Color(white: 0.87) : Color(white: 0.35))
                .frame(width: 34, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.22)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// Above the pads: auto-strum on and off, its pattern, and its tempo (drag the
/// number, or tap TAP in time).
private struct AutoStrumBar: View {
    @ObservedObject var player: HarpPlayer

    var body: some View {
        HStack(spacing: 10) {
            StudioToggleChip(title: "AUTO",
                             isOn: Binding(get: { player.isAutoStrumming },
                                           set: { player.setAutoStrumming($0) }),
                             tint: .green,
                             accessibilityLabel: "Auto-strum: pressing a pad plays the pattern")
            Menu {
                ForEach(AutoStrumPattern.allCases, id: \.self) { pattern in
                    Button {
                        player.setAutoStrumPattern(pattern)
                    } label: {
                        if pattern == player.autoStrumPattern {
                            Label(pattern.title, systemImage: "checkmark")
                        } else {
                            Text(pattern.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(player.autoStrumPattern.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(StudioStyle.displayText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(StudioStyle.scaleText)
                }
                .studioWindow()
            }
            .accessibilityLabel("Pattern: \(player.autoStrumPattern.title)")

            if player.autoStrumPattern.isRhythmic {
                StudioReadout(value: Binding(get: { player.tempo }, set: { player.setTempo($0) }),
                              range: AutoStrum.tempoRange,
                              defaultValue: AutoStrum.defaultTempo,
                              unit: "BPM",
                              accessibilityLabel: "Tempo",
                              format: { String(format: "%.0f", $0) })
                StudioTapButton(title: "TAP") { player.tapTempo() }
                    .accessibilityLabel("Tap tempo")
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    ContentView()
}
