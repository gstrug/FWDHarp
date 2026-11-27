import SwiftUI

/// The mixer, in place of the pads while MIX is lit, so the plate stays playable
/// beside it: strum with one hand and set its level with the other (Graham,
/// 2026-11-21: in a sheet over the screen, the plate could not be heard while its
/// level was set). Master first, then a strip per part (plate, auto-strum, drums,
/// bass).
///
/// Laid out exactly as FWD Sequencer's mixer (Graham, 2026-11-22): 104-point strips
/// with dividers between them, a two-line name, the 180-point fader with its meter and
/// level above, Vol, FX, a 52-point pan knob and M. Below M, each part's instrument,
/// which FWD's strips do not have; auto-strum shows OWN SOUND until it has its own.
struct MixerPanel: View {
    @ObservedObject var player: HarpPlayer
    /// DONE closes the mixer and brings the pads back, as tapping MIX again does.
    let onDone: () -> Void
    private var store: InstrumentStore { player.store }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Scrolls both ways: the instrument buttons under M can run below a short screen.
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    MasterStrip(store: store, levels: store.levels)
                    ForEach(HarpPart.allCases, id: \.self) { part in
                        Divider().padding(.vertical, 8)
                        PartStrip(player: player, store: store, part: part)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 20)
            }
            StudioTapButton(title: "DONE", action: onDone)
                .accessibilityLabel("Close the mixer")
                .helpTag(.mixerDone)
        }
    }
}

/// FWD Sequencer's mixer sizes (SongMixerView, MixerComponents).
private enum StripSize {
    static let width: CGFloat = 104
    static let nameWidth: CGFloat = 80
    static let spacing: CGFloat = 14
    static let faderHeight: CGFloat = 180
    static let knob: CGFloat = 52
}

private let faderMarks: [(Double, String)] = [(6, "+6"), (0, "0"), (-10, "-10"), (-20, "-20"),
                                              (-40, "-40"), (Double(FaderScale.minDB), "-∞")]

/// A strip's name, always two lines tall so every fader starts at the same height.
private struct StripName: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .lineLimit(2, reservesSpace: true)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .frame(width: StripSize.nameWidth)
    }
}

/// The studio fader and its meter side by side, the level above: FWD's FaderWithMeter.
private struct FaderWithMeter<Meter: View>: View {
    @Binding var value: Float
    let accessibilityLabel: String
    @ViewBuilder var meter: Meter

    private var dBBinding: Binding<Double> {
        Binding(get: { Double(FaderScale.dB(fromLinear: value)) },
                set: { value = FaderScale.linear(fromDB: Float($0)) })
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(FaderScale.label(forLinear: value))
                .font(.caption2).monospacedDigit()
                .foregroundStyle(Color(white: 0.85))
            HStack(alignment: .top, spacing: 6) {
                StudioFader(value: dBBinding,
                            range: Double(FaderScale.minDB)...Double(FaderScale.maxDB),
                            defaultValue: 0,   // unity
                            marks: faderMarks,
                            height: StripSize.faderHeight,
                            accessibilityLabel: accessibilityLabel,
                            format: { db in
                                db <= Double(FaderScale.minDB) ? "-∞" : String(format: "%+.1f dB", db)
                            })
                meter
                    .frame(width: 10, height: StripSize.faderHeight - 16)
                    .padding(.top, 8)
            }
        }
    }
}

/// One part's channel strip.
private struct PartStrip: View {
    @ObservedObject var player: HarpPlayer
    @ObservedObject var store: InstrumentStore
    let part: HarpPart

    private var mix: ChannelMix { store.setup.mix(of: part) }
    private var hasOwn: Bool { store.hasOwnSound(part) }

    private var panLabel: String {
        let p = mix.pan
        if abs(p) < 0.05 { return "C" }
        return p < 0 ? "L\(Int(abs(p) * 100))" : "R\(Int(p * 100))"
    }

    var body: some View {
        VStack(spacing: StripSize.spacing) {
            StripName(title: part.title.uppercased())

            Group {
                FaderWithMeter(value: Binding(get: { mix.volume }, set: { store.setVolume($0, for: part) }),
                               accessibilityLabel: "\(part.title) volume") {
                    PartMeter(levels: store.levels, trackID: InstrumentStore.trackID(for: part))
                }
                .midiLearnable(.partVolume(part))
                .helpTag(.mixerFader, instance: part.rawValue)
                Text("Vol").font(.caption2).foregroundStyle(.secondary)
                EffectsToggleButton(store: store, part: part)
                    .midiLearnable(.partEffects(part))
                    .helpTag(.mixerEffects, instance: part.rawValue)
                StudioKnob(value: Binding(get: { Double(mix.pan) }, set: { store.setPan(Float($0), for: part) }),
                           range: -1...1, defaultValue: 0, bipolar: true, size: StripSize.knob,
                           label: "Pan \(panLabel)",
                           format: { _ in panLabel })
                    .midiLearnable(.partPan(part))
                    .helpTag(.mixerPan, instance: part.rawValue)
            }
            // Auto-strum without a sound of its own plays on the plate's channel.
            .disabled(!hasOwn)
            .opacity(hasOwn ? 1 : 0.35)
            // Mute and solo work either way: they hold back the part's own notes.
            MuteSoloChips(store: store, part: part)

            if part == .auto {
                StudioToggleChip(title: "OWN SOUND",
                                 isOn: Binding(get: { hasOwn }, set: { player.setAutoHasOwnSound($0) }),
                                 tint: .green,
                                 accessibilityLabel: "Auto-strum has its own instrument")
                    .helpTag(.mixerOwnSound)
            }
            if hasOwn {
                PartInstrumentButtons(store: store, part: part, stacked: true)
                    .frame(maxWidth: StripSize.width - 8)
                    .helpTag(.mixerInstrument, instance: part.rawValue)
            }
        }
        .frame(width: StripSize.width)
    }
}

private struct PartMeter: View {
    @ObservedObject var levels: LevelMonitor
    let trackID: UUID

    var body: some View {
        SegmentedMeter(level: levels.trackLevels[trackID] ?? .silent, segments: 18)
    }
}

private struct MasterMeter: View {
    @ObservedObject var levels: LevelMonitor

    var body: some View {
        SegmentedMeter(level: levels.masterLevel, segments: 18)
    }
}

/// Everything together, as FWD's master strip. Only its meter watches the levels,
/// so the meter alone redraws 20 times a second, not the fader with it.
private struct MasterStrip: View {
    @ObservedObject var store: InstrumentStore
    let levels: LevelMonitor

    var body: some View {
        VStack(spacing: StripSize.spacing) {
            StripName(title: "MASTER")
            FaderWithMeter(value: Binding(get: { store.setup.masterVolume }, set: { store.setMasterVolume($0) }),
                           accessibilityLabel: "Master volume") {
                MasterMeter(levels: levels)
            }
            .midiLearnable(.masterVolume)
            .helpTag(.mixerMaster)
            Text("Vol").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: StripSize.width)
        .padding(.trailing, 8)
    }
}
