import SwiftUI

/// The chord pads, laid out for the left hand (see ChordPad), each showing its chord's
/// name in the chosen key, with the modifiers held. Many fingers at once: a chord pad
/// with the thumb on a modifier, or a second pad pressed before the first is lifted. Sliding a finger from one pad onto
/// another changes chord.
struct PadsView: View {
    @ObservedObject var player: HarpPlayer
    @State private var touches = PadTouches()
    @ObservedObject private var learn = MIDIControlCenter.shared.learn

    var body: some View {
        GeometryReader { proxy in
            let layout = PadLayout(size: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(ChordPad.allCases, id: \.self) { pad in
                    let frame = layout.frame(of: pad)
                    PadFace(pad: pad,
                            label: pad.degreeLabel(in: player.key),
                            chordName: player.chord(on: pad)?.name(preferFlats: player.key.prefersFlats),
                            isHeld: isHeld(pad),
                            isSounding: pad.isModifier ? player.selection.isInForce(pad)
                                                       : player.selection.current == pad,
                            size: frame.size)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
                MultiTouchSurface(
                    onBegan: { id, point in
                        guard let pad = layout.pad(at: point) else { return }
                        touches.begin(id, on: pad, player: player)
                    },
                    onMoved: { id, point in
                        touches.move(id, to: layout.pad(at: point), player: player)
                    },
                    onEnded: { id in touches.end(id, player: player) }
                )
                .accessibilityHidden(true)
                // MIDI Learn: over the touch surface, so a tap picks a pad to link (a
                // linked button or key then holds the pad as a finger does).
                if learn.isOn {
                    ForEach(ChordPad.allCases, id: \.self) { pad in
                        let frame = layout.frame(of: pad)
                        MIDILearnOverlay(target: .pad(pad), learn: learn)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chord pads")
    }

    private func isHeld(_ pad: ChordPad) -> Bool {
        player.selection.isHeld(pad)
    }
}

/// Which pad each finger is on. A pad counts as held while any finger is on it, so two
/// fingers on one pad do not let it go when the first lifts.
private final class PadTouches {
    private var padForTouch: [ObjectIdentifier: ChordPad] = [:]
    private var fingers: [ChordPad: Int] = [:]

    func begin(_ id: ObjectIdentifier, on pad: ChordPad, player: HarpPlayer) {
        padForTouch[id] = pad
        hold(pad, player)
    }

    func move(_ id: ObjectIdentifier, to pad: ChordPad?, player: HarpPlayer) {
        let before = padForTouch[id]
        guard pad != before else { return }
        // Onto the new pad first, so sliding between chords never passes through none.
        if let pad { padForTouch[id] = pad; hold(pad, player) } else { padForTouch.removeValue(forKey: id) }
        if let before { letGo(before, player) }
    }

    func end(_ id: ObjectIdentifier, player: HarpPlayer) {
        if let pad = padForTouch.removeValue(forKey: id) { letGo(pad, player) }
    }

    private func hold(_ pad: ChordPad, _ player: HarpPlayer) {
        fingers[pad, default: 0] += 1
        if fingers[pad] == 1 { player.press(pad) }
    }

    private func letGo(_ pad: ChordPad, _ player: HarpPlayer) {
        guard let count = fingers[pad] else { return }
        if count <= 1 {
            fingers.removeValue(forKey: pad)
            player.release(pad)
        } else {
            fingers[pad] = count - 1
        }
    }
}

/// One pad, in the studio style: a raised cap that lights when held.
private struct PadFace: View {
    let pad: ChordPad
    /// Its degree in the key: IV I V / ii vi iii, or iv i V / VI III VII in a minor key.
    let label: String
    let chordName: String?
    let isHeld: Bool
    /// The pad whose chord the plate is playing (the last pressed of those held).
    let isSounding: Bool
    let size: CGSize

    private var lit: Color { pad.isModifier ? .orange : StudioStyle.displayText }

    var body: some View {
        let corner = size.width * 0.16
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: corner)
                // Lit while a finger is on it, or while Hold keeps its chord (sounding).
                .fill(isHeld || isSounding
                      ? AnyShapeStyle(lit.opacity(isSounding || pad.isModifier ? 1 : 0.55))
                      : AnyShapeStyle(LinearGradient(colors: [StudioStyle.capTop, StudioStyle.capBottom],
                                                     startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: corner)
                    .stroke(Color.white.opacity(isHeld ? 0.35 : 0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(isHeld ? 0.2 : 0.55), radius: isHeld ? 1 : 3, y: isHeld ? 1 : 3)

            Text(label)
                .font(.system(size: max(10, size.width * 0.13), weight: .semibold))
                .foregroundStyle(isHeld || isSounding ? Color.black.opacity(0.6) : StudioStyle.scaleText)
                .padding(size.width * 0.09)

            Text(pad.modifierTitle ?? chordName ?? "")
                .font(.system(size: size.width * (pad.isModifier ? 0.27 : 0.26), weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(isHeld || isSounding ? Color.black.opacity(0.85) : Color(white: 0.9))
                .frame(width: size.width, height: size.height)
        }
        .scaleEffect(isHeld ? 0.97 : 1)
        .accessibilityElement()
        .accessibilityLabel(pad.modifierTitle ?? chordName ?? label)
        .accessibilityAddTraits(isHeld ? [.isButton, .isSelected] : .isButton)
    }
}
