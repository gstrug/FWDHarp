import SwiftUI

/// Each part's level, mute and solo, to reach while playing (Graham, 2026-11-27: the
/// mixer is fine for setting up, but hard to get at mid-song; FWD Sequencer has these
/// on each track). Small upright faders in the room above the pads, which keep their
/// portrait size: a row of horizontal sliders pushed the plate off an 11-inch screen.
/// The same settings as the mixer, so a change in one shows in the other.
struct LiveMixStrips: View {
    @ObservedObject var player: HarpPlayer

    private var store: InstrumentStore { player.store }
    /// The name above each fader and M S below it.
    private static let around: CGFloat = 62

    var body: some View {
        GeometryReader { geometry in
            let fader = min(220, geometry.size.height - Self.around)
            // Too little room (a narrow window): the mixer still has them all.
            if fader >= 60 {
                HStack(alignment: .bottom, spacing: 16) {
                    ForEach(HarpPart.allCases, id: \.self) { part in
                        LiveMixStrip(store: store, part: part, faderHeight: fader)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
    }
}

private struct LiveMixStrip: View {
    @ObservedObject var store: InstrumentStore
    let part: HarpPart
    let faderHeight: CGFloat

    private var hasOwn: Bool { store.hasOwnSound(part) }

    private var dB: Binding<Double> {
        Binding(get: { Double(FaderScale.dB(fromLinear: store.setup.mix(of: part).volume)) },
                set: { store.setVolume(FaderScale.linear(fromDB: Float($0)), for: part) })
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(part.title.uppercased())
                .font(.system(size: 10, weight: .bold)).tracking(0.6)
                .foregroundStyle(StudioStyle.scaleText)
                .lineLimit(1)
                .fixedSize()
            StudioFader(value: dB,
                        range: Double(FaderScale.minDB)...Double(FaderScale.maxDB),
                        defaultValue: 0,
                        height: faderHeight,
                        accessibilityLabel: "\(part.title) volume",
                        format: { $0 <= Double(FaderScale.minDB) ? "-∞" : String(format: "%+.1f dB", $0) })
                // Auto-strum without a sound of its own plays at the plate's level.
                .disabled(!hasOwn)
                .opacity(hasOwn ? 1 : 0.35)
                .midiLearnable(.partVolume(part))
                .helpTag(.liveMix, instance: part.rawValue)
            MuteSoloChips(store: store, part: part)
        }
    }
}

/// M and S for one part, in the mixer and in the live mix row. Both also silence the
/// part over MIDI out.
struct MuteSoloChips: View {
    @ObservedObject var store: InstrumentStore
    let part: HarpPart

    var body: some View {
        HStack(spacing: 6) {
            StudioToggleChip(title: "M",
                             isOn: Binding(get: { store.setup.mix(of: part).muted },
                                           set: { store.setMuted($0, for: part) }),
                             tint: .orange,
                             accessibilityLabel: "Mute \(part.title)")
                .midiLearnable(.partMute(part))
                .helpTag(.mixerMute, instance: part.rawValue)
            StudioToggleChip(title: "S",
                             isOn: Binding(get: { store.isSoloed(part) },
                                           set: { store.setSoloed($0, for: part) }),
                             tint: .yellow,
                             accessibilityLabel: "Solo \(part.title)")
                .midiLearnable(.partSolo(part))
                .helpTag(.mixerSolo, instance: part.rawValue)
        }
    }
}
