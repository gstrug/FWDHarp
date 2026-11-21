import SwiftUI

/// The mixer: a strip for each part (the plate, auto-strum) and the master. Each strip
/// has the part's instrument, EDIT and FX, pan, mute and a volume fader with its meter,
/// in FWD Sequencer's studio style. Auto-strum plays through the plate's instrument
/// until OWN SOUND gives it one of its own.
struct MixerView: View {
    @ObservedObject var player: HarpPlayer
    @Environment(\.dismiss) private var dismiss
    private var store: InstrumentStore { player.store }

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(HarpPart.allCases, id: \.self) { part in
                        PartStrip(player: player, store: store, part: part)
                    }
                    MasterStrip(store: store, levels: store.levels)
                }
                .padding(20)
            }
            .background(Color(white: 0.08).ignoresSafeArea())
            .navigationTitle("Mixer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        // The mixer covers the main screen, so it carries the loading lock and the
        // notices too: an instrument loaded from here must block touches here.
        .loadingOverlay(store)
        .storeNotices(store)
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
        VStack(spacing: 14) {
            Text(part.title.uppercased())
                .font(.system(size: 12, weight: .bold)).tracking(1)
                .foregroundStyle(StudioStyle.scaleText)

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
                Text("Plays through the plate's instrument, effects and channel.")
                    .font(.footnote)
                    .foregroundStyle(StudioStyle.scaleText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 180)
            }

            Group {
                StudioKnob(value: Binding(get: { Double(mix.pan) },
                                          set: { store.setPan(Float($0), for: part) }),
                           range: -1...1, defaultValue: 0, bipolar: true, size: 50, label: "PAN",
                           format: { v in
                               abs(v) < 0.02 ? "C" : String(format: "%@%.0f", v < 0 ? "L" : "R", abs(v) * 100)
                           })

                HStack(alignment: .bottom, spacing: 10) {
                    StudioFader(value: Binding(get: { Double(FaderScale.dB(fromLinear: mix.volume)) },
                                               set: { store.setVolume(FaderScale.linear(fromDB: Float($0)), for: part) }),
                                range: Double(FaderScale.minDB)...Double(FaderScale.maxDB),
                                defaultValue: Double(FaderScale.dB(fromLinear: 0.8)),
                                marks: [(6, "+6"), (0, "0"), (-12, "-12"), (-30, "-30"), (-60, "-∞")],
                                height: 220,
                                accessibilityLabel: "\(part.title) volume",
                                format: { $0 <= Double(FaderScale.minDB) ? "-∞" : String(format: "%+.1f dB", $0) })
                    PartMeter(levels: store.levels, trackID: InstrumentStore.trackID(for: part))
                        .frame(width: 12, height: 220)
                }

                StudioToggleChip(title: "M",
                                 isOn: Binding(get: { mix.muted }, set: { store.setMuted($0, for: part) }),
                                 tint: .yellow,
                                 accessibilityLabel: "Mute \(part.title)")
            }
            .disabled(!hasOwn)
            .opacity(hasOwn ? 1 : 0.35)
        }
        .padding(16)
        .frame(width: 210)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
    }
}

private struct PartMeter: View {
    @ObservedObject var levels: LevelMonitor
    let trackID: UUID

    var body: some View {
        SegmentedMeter(level: levels.trackLevels[trackID] ?? .silent, segments: 18)
    }
}

/// Everything together.
private struct MasterStrip: View {
    @ObservedObject var store: InstrumentStore
    @ObservedObject var levels: LevelMonitor

    var body: some View {
        VStack(spacing: 14) {
            Text("MASTER")
                .font(.system(size: 12, weight: .bold)).tracking(1)
                .foregroundStyle(StudioStyle.scaleText)
            HStack(alignment: .bottom, spacing: 10) {
                StudioFader(value: Binding(get: { Double(FaderScale.dB(fromLinear: store.setup.masterVolume)) },
                                           set: { store.setMasterVolume(FaderScale.linear(fromDB: Float($0))) }),
                            range: Double(FaderScale.minDB)...Double(FaderScale.maxDB),
                            defaultValue: 0,
                            marks: [(6, "+6"), (0, "0"), (-12, "-12"), (-30, "-30"), (-60, "-∞")],
                            height: 220,
                            accessibilityLabel: "Master volume",
                            format: { $0 <= Double(FaderScale.minDB) ? "-∞" : String(format: "%+.1f dB", $0) })
                SegmentedMeter(level: levels.masterLevel, segments: 18)
                    .frame(width: 12, height: 220)
            }
        }
        .padding(16)
        .frame(width: 150)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
    }
}
