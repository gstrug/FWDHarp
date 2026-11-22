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
            MIDILearnBanner()
            HStack(spacing: 24) {
                // MIX puts the mixer here, in place of the pads, so the plate beside it
                // can be played while its level is set.
                VStack(alignment: .leading, spacing: 10) {
                    AutoStrumBar(player: player)
                    RhythmControls(player: player)
                    if showMixer {
                        MixerPanel(player: player, onDone: { showMixer = false })
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        PadsView(player: player)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                // The controls may be wider than the plate; they line up with its right
                // edge and take the room they need from the pads.
                VStack(alignment: .trailing, spacing: 10) {
                    PlateControls(player: player)
                        .fixedSize()
                    StrumPlateView(player: player)
                        .frame(width: 300)
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(20)
        }
        .background(Color(white: 0.08).ignoresSafeArea())
        .sheet(isPresented: $showCredits) { CreditsView() }
        .sheet(isPresented: $showMIDI) { MIDISettingsView(player: player) }
        // MIDI in: controllers, MIDI Learn and the clock, for this harp.
        .onAppear { MIDIControlCenter.shared.start(player: player) }
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
        // Each part's instrument over its own side of the screen: auto-strum's on the
        // left over the pads, the plate's on the right over the plate, and the app's
        // own buttons in the middle (Graham, 2026-11-22). Same side padding as the pads
        // and plate below, so the edges line up.
        HStack(spacing: 12) {
            AutoInstrumentGroup(player: player)
            Spacer(minLength: 8)
            HStack(spacing: 12) {
                StudioToggleChip(title: "MIX", isOn: $showMixer, tint: StudioStyle.displayText,
                                 accessibilityLabel: "Mixer, in place of the pads")
                // Lit while MIDI out is on or a MIDI clock is followed; opens MIDI settings.
                StudioChipLabel(title: "MIDI", tint: .cyan,
                                look: store.midiOut.enabled || player.isFollowingClock ? .on : .off)
                    .onTapGesture { showMIDI = true }
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("MIDI settings")
                    .accessibilityValue(store.midiOut.enabled ? "Sending" : "Not sending")
                // FWD Sequencer's panic button: the red stop sign.
                Button { player.panic() } label: {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Panic, stop all notes")
                .midiLearnable(.panic)
                CPUReadout()
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                PartInstrumentButtons(store: store, part: .plate)
                EffectsToggleButton(store: store, part: .plate)
                    .midiLearnable(.partEffects(.plate))
                // About and Credits, at the far right (Graham, 2026-11-22).
                Button { showCredits = true } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(Color(white: 0.7))
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("FWD Harp: About and Credits")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

/// Auto-strum's instrument, EDIT and FX, at the left of the top bar over the pads.
/// Until it has a sound of its own it plays through the plate's; choosing an
/// instrument here gives it one (the mixer's OWN SOUND sends it back).
private struct AutoInstrumentGroup: View {
    @ObservedObject var player: HarpPlayer
    private var store: InstrumentStore { player.store }

    var body: some View {
        HStack(spacing: 10) {
            PartInstrumentButtons(store: store, part: .auto,
                                  beforeChoosing: { player.setAutoHasOwnSound(true) })
            if store.hasOwnSound(.auto) {
                EffectsToggleButton(store: store, part: .auto)
                    .midiLearnable(.partEffects(.auto))
            }
        }
    }
}

/// The key the pads play in.
private struct KeyMenu: View {
    @ObservedObject var player: HarpPlayer

    var body: some View {
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
                WidestText(player.key.name, all: MajorKey.all.map(\.name))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioStyle.displayText)
            }
            .studioWindow()
        }
        .accessibilityLabel("Key: \(player.key.name) major")
    }
}

/// How many strings the plate has, whatever it plays: always that many, so the
/// strings never crowd (Graham, 2026-11-21).
private struct StringsMenu: View {
    @ObservedObject var player: HarpPlayer

    var body: some View {
        StudioMenu(title: "STRINGS \(player.stringCount)", label: "Strings on the plate",
                   titles: StrumPlate.stringChoices.map { "STRINGS \($0)" }) {
            ForEach(StrumPlate.stringChoices, id: \.self) { count in
                Button { player.setPlateStrings(count) } label: {
                    if count == player.stringCount {
                        Label("\(count) strings", systemImage: "checkmark")
                    } else {
                        Text("\(count) strings")
                    }
                }
            }
        }
    }
}

/// What the plate plays, after KEY: the chord held, or a scale in the key.
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
                WidestText(player.plateScale.title, all: PlateScale.allCases.map(\.title))
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

/// Above the plate, in three rows (Graham, 2026-11-22): the key and what the plate
/// plays; the order of its notes and how long they ring; its strings and octave.
private struct PlateControls: View {
    @ObservedObject var player: HarpPlayer

    var body: some View {
        // Two rows in columns (Graham, 2026-11-22): KEY over the scale ("Chord"),
        // the order over STRINGS, RING over OCT.
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                KeyMenu(player: player)
                StudioMenu(title: player.platePattern.title, label: "Plate order",
                           titles: PlatePattern.allCases.map(\.title)) {
                    ForEach(PlatePattern.allCases, id: \.self) { pattern in
                        check(pattern.title, pattern == player.platePattern) { player.setPlatePattern(pattern) }
                    }
                }
                StudioMenu(title: "RING \(player.plateRing.title)", label: "How long plate notes ring",
                           titles: PlateRing.allCases.map { "RING \($0.title)" }) {
                    ForEach(PlateRing.allCases, id: \.self) { ring in
                        check(ring.title, ring == player.plateRing) { player.setPlateRing(ring) }
                    }
                }
            }
            GridRow {
                ScaleMenu(player: player)
                StringsMenu(player: player)
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
        .midiLearnable(step > 0 ? .octaveUp : .octaveDown)
    }
}

/// A menu in the studio style: its current choice in a dark window, with a chevron.
private struct StudioMenu<Items: View>: View {
    let title: String
    let label: String
    /// Every title it can show: its width is the widest, so nothing beside it moves
    /// when the choice changes.
    var titles: [String] = []
    @ViewBuilder let items: Items

    var body: some View {
        Menu { items } label: {
            HStack(spacing: 6) {
                WidestText(title, all: titles)
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

/// `text`, taking the width of the widest of `all`, so the controls around it stay
/// put when it changes (Graham, 2026-11-22: the pads resized when the scale changed).
private struct WidestText: View {
    let text: String
    let all: [String]

    init(_ text: String, all: [String]) {
        self.text = text
        self.all = all
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(all, id: \.self) { Text($0).hidden() }
            Text(text)
        }
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
                .midiLearnable(.autoStrum)
            StudioToggleChip(title: "HOLD",
                             isOn: Binding(get: { player.selection.isHolding },
                                           set: { player.setHolding($0) }),
                             tint: .orange,
                             accessibilityLabel: "Hold: keep the last chord after lifting your hand")
                .midiLearnable(.hold)
            // No STOP here: HOLD off lets the kept chord go, and with HOLD on it ends
            // when the drums stop (Graham, 2026-11-22).
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

            // One tempo for auto-strum and the rhythm section. Following a MIDI clock,
            // it shows the clock's tempo and can't be changed here.
            let following = player.isFollowingClock
            StudioReadout(value: Binding(get: { following ? (player.clockTempo ?? player.tempo) : player.tempo },
                                         set: { if !following { player.setTempo($0) } }),
                          range: AutoStrum.tempoRange,
                          defaultValue: AutoStrum.defaultTempo,
                          unit: "BPM",
                          accessibilityLabel: following ? "Tempo, from the MIDI clock" : "Tempo",
                          format: { String(format: following ? "%.1f" : "%.0f", $0) })
                .disabled(following)
                .midiLearnable(.tempo)
            if following {
                StudioChipLabel(title: "CLOCK", tint: .cyan, look: player.clockTempo == nil ? .off : .on)
                    .accessibilityLabel(player.clockTempo == nil ? "Waiting for MIDI clock" : "Following MIDI clock")
            } else {
                StudioTapButton(title: "TAP") { player.tapTempo() }
                    .accessibilityLabel("Tap tempo")
                    .midiLearnable(.tapTempo)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The rhythm section: drums and a bass that follows the chord pads, on the same
/// clock as auto-strum. START plays at once (with the style's intro first if INTRO is
/// lit); SYNC instead waits for the first pad (auto-strum on) or the first strum (off).
/// A/B and a new style change at the next bar; FILL fills to the end of the bar.
private struct RhythmControls: View {
    @ObservedObject var player: HarpPlayer

    private var running: Bool { player.rhythm.running }

    var body: some View {
        HStack(spacing: 10) {
            StudioToggleChip(title: running ? "STOP" : "START",
                             isOn: Binding(get: { running }, set: { _ in player.toggleRhythm() }),
                             tint: .green,
                             accessibilityLabel: "Start or stop the drums and bass")
                .midiLearnable(.rhythmStartStop)
            StudioToggleChip(title: "SYNC",
                             isOn: Binding(get: { player.isRhythmArmed }, set: { player.armRhythm($0) }),
                             tint: .cyan,
                             accessibilityLabel: "Start the drums and bass with the first pad or strum")
                .disabled(running)
                .opacity(running ? 0.45 : 1)
                .midiLearnable(.rhythmSync)
            Menu {
                ForEach(RhythmStyle.allCases, id: \.self) { style in
                    Button {
                        player.setRhythmStyle(style)
                    } label: {
                        if style == player.rhythmStyle {
                            Label(style.title, systemImage: "checkmark")
                        } else {
                            Text(style.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(player.rhythmStyle.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(StudioStyle.displayText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(StudioStyle.scaleText)
                }
                .studioWindow()
            }
            .accessibilityLabel("Rhythm style: \(player.rhythmStyle.title)")
            ForEach(RhythmVariation.allCases, id: \.self) { variation in
                StudioToggleChip(title: variation.title,
                                 isOn: Binding(get: { player.rhythmVariation == variation },
                                               set: { _ in player.setRhythmVariation(variation) }),
                                 tint: StudioStyle.displayText,
                                 accessibilityLabel: "Variation \(variation.title)")
                    .midiLearnable(variation == .a ? .variationA : .variationB)
            }
            // INTRO before the start (it goes off once played); then OUTRO, which plays
            // the style's ending and stops the band (Graham, 2026-11-22).
            if running && !player.rhythm.intro {
                StudioToggleChip(title: "OUTRO",
                                 isOn: Binding(get: { player.rhythm.outro }, set: { _ in player.outro() }),
                                 tint: .orange,
                                 accessibilityLabel: "Play the ending and stop")
                    .midiLearnable(.introOutro)
            } else {
                StudioToggleChip(title: "INTRO",
                                 isOn: Binding(get: { player.rhythmIntro }, set: { player.setRhythmIntro($0) }),
                                 tint: .orange,
                                 accessibilityLabel: "Play the style's intro bar first")
                    .allowsHitTesting(!running)
                    .midiLearnable(.introOutro)
            }
            StudioTapButton(title: "FILL") { player.fill() }
                .disabled(!running || player.rhythm.intro || player.rhythm.outro)
                .opacity(!running || player.rhythm.intro || player.rhythm.outro ? 0.45 : 1)
                .accessibilityLabel("Fill to the end of the bar")
                .midiLearnable(.fill)
            BeatLights(position: player.rhythm, beats: player.rhythmStyle.beatsPerBar)
            Spacer(minLength: 0)
        }
    }
}

/// A light per beat of the bar: the one playing lit, the first brighter.
private struct BeatLights: View {
    let position: RhythmPosition
    let beats: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(beats, position.beat + 1), id: \.self) { beat in
                Circle()
                    .fill(color(for: beat))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(for beat: Int) -> Color {
        guard position.running, beat == position.beat else { return Color(white: 0.22) }
        if position.intro || position.fill || position.outro { return .orange }
        return beat == 0 ? .green : Color.green.opacity(0.6)
    }
}

/// Process CPU load, as a fraction of one core, as in FWD Sequencer. Hosted plugins
/// are where the app spends its time; crackle and static start when this runs out.
private struct CPUReadout: View {
    @StateObject private var monitor = CPUMonitor()

    private var tint: Color {
        monitor.load >= CPUMonitor.warningLoad ? .orange
            : monitor.load >= CPUMonitor.warningLoad * 0.7 ? .yellow : Color(white: 0.6)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "cpu").font(.caption2)
            Text("\(Int((monitor.load * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                // Fixed width so the bar does not shuffle as the number changes.
                .frame(minWidth: 34, alignment: .trailing)
        }
        .foregroundStyle(tint)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Processor load")
        .accessibilityValue("\(Int((monitor.load * 100).rounded())) percent")
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

#Preview {
    ContentView()
}
