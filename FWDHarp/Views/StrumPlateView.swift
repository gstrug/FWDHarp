import SwiftUI

/// The strum plate: strings across a tall strip, low at the bottom. Touch a string to
/// pluck it, or sweep across them to strum; further right is louder, and sliding a
/// held finger sideways swells or softens the sound. Every finger is followed, and a
/// fast sweep that skips strings between touch reports still plays each one, in
/// order. Held strings follow a chord change.
struct StrumPlateView: View {
    @ObservedObject var player: HarpPlayer

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let count = player.stringCount
            let notes = player.plateNotes
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [StudioStyle.trackTop, StudioStyle.trackBottom],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(LinearGradient(colors: [Color.black.opacity(0.9), Color.white.opacity(0.08)],
                                               startPoint: .top, endPoint: .bottom), lineWidth: 1))

                PlateStrings(lights: player.plateLights, notes: notes, count: count,
                             preferFlats: player.key.prefersFlats, size: size)

                if notes.isEmpty {
                    Text("Hold a chord pad, then strum here")
                        .font(.callout)
                        .foregroundStyle(StudioStyle.scaleText)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                }

                // Each finger is followed by the harp itself (HarpPlayer.touchBegan …), so
                // a chord change can retune the strings held.
                MultiTouchSurface(
                    onBegan: { id, point in
                        let spot = place(point, in: size, strings: count)
                        player.touchBegan(id, string: spot.string, loudness: spot.loudness)
                    },
                    onMoved: { id, point in
                        let spot = place(point, in: size, strings: count)
                        player.touchMoved(id, string: spot.string, loudness: spot.loudness)
                    },
                    onEnded: { id in player.touchEnded(id) }
                )
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Strum plate")
        .accessibilityValue(player.chord.map { "Playing \($0.name(preferFlats: player.key.prefersFlats))" }
                            ?? "No chord held")
    }

    private func place(_ point: CGPoint, in size: CGSize, strings: Int) -> (string: Int, loudness: Double) {
        let fromBottom = size.height > 0 ? 1 - Double(point.y / size.height) : 0
        let across = size.width > 0 ? Double(point.x / size.width) : 0
        return (StrumPlate.string(atHeight: fromBottom, strings: strings), min(max(across, 0), 1))
    }
}

/// The strings, lit under the fingers. Watches only the lights, so a strum redraws
/// just the strings.
private struct PlateStrings: View {
    @ObservedObject var lights: PlateLights
    let notes: [Int]
    let count: Int
    let preferFlats: Bool
    let size: CGSize

    var body: some View {
        let band = size.height / CGFloat(max(count, 1))
        ForEach(0..<count, id: \.self) { string in
            StringLine(note: notes.indices.contains(string) ? notes[string] : nil,
                       preferFlats: preferFlats,
                       isTouched: lights.touched.contains(string))
                .frame(width: size.width, height: band)
                .position(x: size.width / 2, y: size.height - (CGFloat(string) + 0.5) * band)
        }
    }
}

/// One string: a line, its note's name at the left, lit while touched.
private struct StringLine: View, Equatable {
    let note: Int?
    let preferFlats: Bool
    let isTouched: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(note == nil ? Color(white: 0.22)
                      : isTouched ? StudioStyle.displayText : Color(white: 0.55))
                .frame(height: isTouched ? 3 : 1.5)
                .shadow(color: isTouched ? StudioStyle.displayText : .clear, radius: 4)
                .padding(.horizontal, 12)
            if let note {
                Text(NoteNames.name(note % 12, preferFlats: preferFlats))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isTouched ? StudioStyle.displayText : StudioStyle.scaleText)
                    .padding(.horizontal, 4)
                    .background(StudioStyle.trackTop.opacity(0.9), in: Capsule())
                    .padding(.leading, 16)
            }
        }
        .allowsHitTesting(false)
    }
}
