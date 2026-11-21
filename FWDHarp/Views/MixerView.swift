import SwiftUI

/// The mixer, in place of the pads while MIX is lit, so the plate stays playable
/// beside it: strum with one hand and set its level with the other (Graham,
/// 2026-11-21: in a sheet over the screen, the plate could not be heard while its
/// level was set). Master first, then a strip per part, all the same size, with room
/// for the rhythm section's drums and bass to join (design brief). In FWD Sequencer's
/// studio style. Auto-strum plays through the plate's instrument until OWN SOUND gives
/// it one of its own.
struct MixerPanel: View {
    @ObservedObject var player: HarpPlayer
    private var store: InstrumentStore { player.store }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                MasterStrip(store: store, levels: store.levels)
                ForEach(HarpPart.allCases, id: \.self) { part in
                    PartStrip(player: player, store: store, part: part)
                }
            }
        }
    }
}

/// The shape every strip shares, so their faders line up: a heading, a top area for
/// the instrument, then pan, the fader with its meter, and mute.
private enum StripSize {
    static let width: CGFloat = 150
    static let topHeight: CGFloat = 150
    static let panHeight: CGFloat = 76
    static let faderHeight: CGFloat = 200
}

private let faderMarks: [(Double, String)] = [(6, "+6"), (0, "0"), (-12, "-12"), (-30, "-30"), (-60, "-∞")]

private func dBText(_ value: Double) -> String {
    value <= Double(FaderScale.minDB) ? "-∞" : String(format: "%+.1f dB", value)
}

private struct StripShell<Top: View, Pan: View, Fader: View, Mute: View>: View {
    let title: String
    @ViewBuilder let top: Top
    @ViewBuilder let pan: Pan
    @ViewBuilder let fader: Fader
    @ViewBuilder let mute: Mute

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold)).tracking(1)
                .foregroundStyle(StudioStyle.scaleText)
                .lineLimit(1)
            VStack(spacing: 8) { top }
                .frame(height: StripSize.topHeight, alignment: .top)
            pan.frame(height: StripSize.panHeight)
            fader.frame(height: StripSize.faderHeight)
            mute.frame(height: 34)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: StripSize.width)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
    }
}

/// One part's channel strip.
private struct PartStrip: View {
    @ObservedObject var player: HarpPlayer
    @ObservedObject var store: InstrumentStore
    let part: HarpPart

    private var mix: ChannelMix { store.setup.mix(of: part) }
    private var hasOwn: Bool { store.hasOwnSound(part) }

    var body: some View {
        StripShell(title: part.title.uppercased()) {
            if part == .auto {
                StudioToggleChip(title: "OWN SOUND",
                                 isOn: Binding(get: { hasOwn }, set: { player.setAutoHasOwnSound($0) }),
                                 tint: .green,
                                 accessibilityLabel: "Auto-strum has its own instrument")
            }
            if hasOwn {
                PartInstrumentButtons(store: store, part: part, stacked: true)
                EffectsToggleButton(store: store, part: part)
            } else {
                Text("Plays through the plate's instrument and channel.")
                    .font(.footnote)
                    .foregroundStyle(StudioStyle.scaleText)
                    .multilineTextAlignment(.center)
            }
        } pan: {
            StudioKnob(value: Binding(get: { Double(mix.pan) }, set: { store.setPan(Float($0), for: part) }),
                       range: -1...1, defaultValue: 0, bipolar: true, size: 46, label: "PAN",
                       format: { v in
                           abs(v) < 0.02 ? "C" : String(format: "%@%.0f", v < 0 ? "L" : "R", abs(v) * 100)
                       })
                .disabled(!hasOwn).opacity(hasOwn ? 1 : 0.35)
        } fader: {
            HStack(alignment: .bottom, spacing: 8) {
                StudioFader(value: Binding(get: { Double(FaderScale.dB(fromLinear: mix.volume)) },
                                           set: { store.setVolume(FaderScale.linear(fromDB: Float($0)), for: part) }),
                            range: Double(FaderScale.minDB)...Double(FaderScale.maxDB),
                            defaultValue: Double(FaderScale.dB(fromLinear: 0.8)),
                            marks: faderMarks,
                            height: StripSize.faderHeight,
                            accessibilityLabel: "\(part.title) volume",
                            format: dBText)
                PartMeter(levels: store.levels, trackID: InstrumentStore.trackID(for: part))
                    .frame(width: 12, height: StripSize.faderHeight)
            }
            .disabled(!hasOwn).opacity(hasOwn ? 1 : 0.35)
        } mute: {
            StudioToggleChip(title: "M",
                             isOn: Binding(get: { mix.muted }, set: { store.setMuted($0, for: part) }),
                             tint: .yellow,
                             accessibilityLabel: "Mute \(part.title)")
                .disabled(!hasOwn).opacity(hasOwn ? 1 : 0.35)
        }
    }
}

private struct PartMeter: View {
    @ObservedObject var levels: LevelMonitor
    let trackID: UUID

    var body: some View {
        SegmentedMeter(level: levels.trackLevels[trackID] ?? .silent, segments: 18)
    }
}

/// Everything together. The same size as the part strips, so the faders line up.
private struct MasterStrip: View {
    @ObservedObject var store: InstrumentStore
    @ObservedObject var levels: LevelMonitor

    var body: some View {
        // Clear spaces rather than EmptyView, which has no size: the strip's back plate
        // came up shorter than the others.
        StripShell(title: "MASTER") {
            Color.clear
        } pan: {
            Color.clear
        } fader: {
            HStack(alignment: .bottom, spacing: 8) {
                StudioFader(value: Binding(get: { Double(FaderScale.dB(fromLinear: store.setup.masterVolume)) },
                                           set: { store.setMasterVolume(FaderScale.linear(fromDB: Float($0))) }),
                            range: Double(FaderScale.minDB)...Double(FaderScale.maxDB),
                            defaultValue: 0,
                            marks: faderMarks,
                            height: StripSize.faderHeight,
                            accessibilityLabel: "Master volume",
                            format: dBText)
                SegmentedMeter(level: levels.masterLevel, segments: 18)
                    .frame(width: 12, height: StripSize.faderHeight)
            }
        } mute: {
            Color.clear
        }
    }
}
