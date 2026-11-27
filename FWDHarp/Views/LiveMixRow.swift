import SwiftUI

/// Each part's level, mute and solo in one slim row above the pads, to reach while
/// playing (Graham, 2026-11-27: the mixer is fine for setting up, but hard to get at
/// mid-song; FWD Sequencer has these on each track). The same settings as the mixer,
/// so a change in one shows in the other. Portrait: two rows of two.
struct LiveMixRow: View {
    @ObservedObject var player: HarpPlayer
    var narrow = false

    private var store: InstrumentStore { player.store }

    var body: some View {
        let parts = HarpPart.allCases
        Group {
            if narrow {
                Grid(horizontalSpacing: 10, verticalSpacing: 8) {
                    ForEach(Array(stride(from: 0, to: parts.count, by: 2)), id: \.self) { first in
                        GridRow {
                            ForEach(parts[first..<min(first + 2, parts.count)], id: \.self) { part in
                                LiveMixItem(store: store, part: part)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ForEach(parts, id: \.self) { part in LiveMixItem(store: store, part: part) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveMixItem: View {
    @ObservedObject var store: InstrumentStore
    let part: HarpPart

    private var hasOwn: Bool { store.hasOwnSound(part) }

    var body: some View {
        HStack(spacing: 6) {
            Text(part.title.uppercased())
                .font(.system(size: 10, weight: .bold)).tracking(0.6)
                .foregroundStyle(StudioStyle.scaleText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 46, alignment: .leading)
            StudioSlider.volume(Binding(get: { store.setup.mix(of: part).volume },
                                        set: { store.setVolume($0, for: part) }),
                                label: "\(part.title) volume")
                .frame(minWidth: 60, maxWidth: .infinity)
                .frame(height: 34)
                // Auto-strum without a sound of its own plays at the plate's level.
                .disabled(!hasOwn)
                .opacity(hasOwn ? 1 : 0.35)
                .midiLearnable(.partVolume(part))
                .helpTag(.liveMix, instance: part.rawValue)
            MuteSoloChips(store: store, part: part)
        }
        .frame(maxWidth: .infinity)
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
