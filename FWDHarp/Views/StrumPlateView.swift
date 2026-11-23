import SwiftUI

/// The strum plate: strings across a tall strip, low at the bottom. Touch a string to
/// pluck it, or sweep across them to strum; further right is louder. Every finger is
/// followed, and a fast sweep that skips strings between touch reports still plays
/// each one, in order.
struct StrumPlateView: View {
    @ObservedObject var player: HarpPlayer
    @State private var touches = PlateTouches()

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

                MultiTouchSurface(
                    onBegan: { id, point in
                        touches.begin(id, at: place(point, in: size, strings: count), player: player)
                    },
                    onMoved: { id, point in
                        touches.move(id, to: place(point, in: size, strings: count), player: player)
                    },
                    onEnded: { id in touches.end(id, player: player) }
                )
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Strum plate")
        .accessibilityValue(player.chord.map { "Playing \($0.name(preferFlats: player.key.prefersFlats))" }
                            ?? "No chord held")
    }

    private func place(_ point: CGPoint, in size: CGSize, strings: Int) -> PlateTouches.Place {
        let fromBottom = size.height > 0 ? 1 - Double(point.y / size.height) : 0
        let across = size.width > 0 ? Double(point.x / size.width) : 0
        return .init(string: StrumPlate.string(atHeight: fromBottom, strings: strings),
                     loudness: min(max(across, 0), 1))
    }
}

/// The string each finger is on, and the note it started there.
private final class PlateTouches {
    struct Place { let string: Int; let loudness: Double }
    private var stringForTouch: [ObjectIdentifier: Int] = [:]
    private var noteForTouch: [ObjectIdentifier: UInt8] = [:]

    func begin(_ id: ObjectIdentifier, at place: Place, player: HarpPlayer) {
        stringForTouch[id] = place.string
        noteForTouch[id] = player.pluck(string: place.string, loudness: place.loudness)
        light(player)
    }

    func move(_ id: ObjectIdentifier, to place: Place, player: HarpPlayer) {
        guard let before = stringForTouch[id], before != place.string else { return }
        // The new string sounds before the old one is let go, so a note on both
        // strings is never cut. Strings swept past in between are let go at once.
        let crossed = StrumPlate.strings(crossedFrom: before, to: place.string)
        var landed: UInt8?
        for string in crossed {
            let note = player.pluck(string: string, loudness: place.loudness)
            if string == place.string { landed = note } else if let note { player.lift(note: note) }
        }
        if let previous = noteForTouch[id] { player.lift(note: previous) }
        stringForTouch[id] = place.string
        noteForTouch[id] = landed
        light(player)
    }

    func end(_ id: ObjectIdentifier, player: HarpPlayer) {
        stringForTouch.removeValue(forKey: id)
        if let note = noteForTouch.removeValue(forKey: id) { player.lift(note: note) }
        light(player)
    }

    private func light(_ player: HarpPlayer) {
        player.setTouchedStrings(Set(stringForTouch.values))
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
