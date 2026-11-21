import SwiftUI

/// The harp: chord pads under the left hand, the strum plate on the right, and the
/// plate's instrument, the key and the mixer along the top. Everything set is
/// remembered between launches, except HOLD and AUTO, which start off.
struct ContentView: View {
    @StateObject private var player = HarpPlayer()
    private var store: InstrumentStore { player.store }
    @State private var showMixer = false
    @State private var showCredits = false
    @State private var showMIDI = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 24) {
                // MIX puts the mixer here, in place of the pads, so the plate beside it
                // can be played while its level is set.
                VStack(alignment: .leading, spacing: 10) {
                    AutoStrumBar(player: player)
                    if showMixer {
                        MixerPanel(player: player)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        PadsView(player: player)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
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
        .sheet(isPresented: $showCredits) { CreditsView() }
        .sheet(isPresented: $showMIDI) { MIDIOutView(store: store) }
        .loadingOverlay(store)
        // A safe moment to keep the instruments' sounds and save (FWD lesson 3).
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                player.setAutoStrumming(false)
                player.releaseAll()
                store.captureAndSave()
            }
        }
        .storeNotices(store)
    }

    private var topBar: some View {
        // The app's controls on the left; the plate's on the right, over the plate.
        // Same side padding as the pads and plate below, so the edges line up.
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Button { showCredits = true } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(Color(white: 0.7))
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("FWD Harp: About and Credits")
                keyMenu
                StudioToggleChip(title: "MIX", isOn: $showMixer, tint: StudioStyle.displayText,
                                 accessibilityLabel: "Mixer, in place of the pads")
                // Lit while MIDI out is on; opens its settings.
                StudioChipLabel(title: "MIDI", tint: .cyan, look: store.midiOut.enabled ? .on : .off)
                    .onTapGesture { showMIDI = true }
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("MIDI out")
                    .accessibilityValue(store.midiOut.enabled ? "On" : "Off")
                StudioTapButton(title: "PANIC") { player.panic() }
                    .accessibilityLabel("MIDI panic: stop every sounding note")
            }
            Spacer(minLength: 8)
            // Everything that belongs to the plate, on the right over it: its range and
            // scale, then its instrument, EDIT and FX (Graham, 2026-11-21).
            HStack(spacing: 10) {
                RangeChips(player: player)
                ScaleMenu(player: player)
                PartInstrumentButtons(store: store, part: .plate)
                EffectsToggleButton(store: store, part: .plate)
            }
        }
        .padding(.horizontal, 20)
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

/// Above the plate: the order of its notes, how long they ring, and the octave
/// buttons that move it.
private struct PlateControls: View {
    @ObservedObject var player: HarpPlayer

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                StudioMenu(title: player.platePattern.title, label: "Plate order") {
                    ForEach(PlatePattern.allCases, id: \.self) { pattern in
                        check(pattern.title, pattern == player.platePattern) { player.setPlatePattern(pattern) }
                    }
                }
                StudioMenu(title: "RING \(player.plateRing.title)", label: "How long plate notes ring") {
                    ForEach(PlateRing.allCases, id: \.self) { ring in
                        check(ring.title, ring == player.plateRing) { player.setPlateRing(ring) }
                    }
                }
            }
            HStack(spacing: 8) {
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
            }
        }
    }

    private func check(_ title: String, _ selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
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

/// A menu in the studio style: its current choice in a dark window, with a chevron.
private struct StudioMenu<Items: View>: View {
    let title: String
    let label: String
    @ViewBuilder let items: Items

    var body: some View {
        Menu { items } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StudioStyle.displayText)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(StudioStyle.scaleText)
            }
            .studioWindow()
        }
        .accessibilityLabel("\(label): \(title)")
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
            StudioToggleChip(title: "HOLD",
                             isOn: Binding(get: { player.selection.isHolding },
                                           set: { player.setHolding($0) }),
                             tint: .orange,
                             accessibilityLabel: "Hold: keep the last chord after lifting your hand")
            // With HOLD on the kept chord never ends by itself: STOP lets it go, which
            // ends auto-strum's pattern too. HOLD stays on for the next chord.
            StudioTapButton(title: "STOP") { player.stopKeptChord() }
                .disabled(player.selection.latched == nil)
                .opacity(player.selection.latched == nil ? 0.45 : 1)
                .accessibilityLabel("Stop the kept chord")
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
