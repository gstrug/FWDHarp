import SwiftUI

// Copied from FWD Sequencer (MixerComponents.swift) on 2026-11-20: the parts the
// studio controls need.

/// Latched clip state shared by both meter styles.
///
/// A clip indicator has to persist — an over lasts one buffer and would otherwise
/// flash past unseen. It clears itself once the signal has stayed below full scale
/// for a moment, so pulling a hot track down visibly resolves it, and it can also
/// be cleared by tapping the meter.
struct ClipLatch {
    private(set) var isLit = false
    private var lastOver = Date.distantPast
    /// How long the signal must stay clean before the indicator clears itself.
    static let clearAfter: TimeInterval = 2.0

    mutating func update(with level: AudioLevel, now: Date = Date()) {
        if level.isOver {
            isLit = true
            lastOver = now
        } else if isLit, now.timeIntervalSince(lastOver) > Self.clearAfter {
            isLit = false
        }
    }

    mutating func clear() { isLit = false; lastOver = .distantPast }
}

/// Faders operate in decibels, not in linear gain.
///
/// A linear 0...1 fader puts every useful mixing decision in the bottom of its
/// travel — a plugin that needs -20 dB sits at 0.1, with almost no resolution left
/// to trim it. Storage stays linear (so saved songs are unchanged); only the
/// control is logarithmic, with a little headroom for quiet instruments.
enum FaderScale {
    static let minDB: Float = -60      // treated as silence
    static let maxDB: Float = 6

    static func dB(fromLinear linear: Float) -> Float {
        linear <= 0 ? minDB : max(minDB, 20 * log10(linear))
    }

    static func linear(fromDB db: Float) -> Float {
        db <= minDB ? 0 : pow(10, db / 20)
    }

    /// Wraps a linear gain so a Slider can drive it in dB.
    static func binding(_ gain: Binding<Float>) -> Binding<Float> {
        Binding(get: { dB(fromLinear: gain.wrappedValue) },
                set: { gain.wrappedValue = linear(fromDB: $0) })
    }

    static func label(forLinear linear: Float) -> String {
        let db = dB(fromLinear: linear)
        if db <= minDB { return "-∞" }
        return String(format: "%+.1f", db)
    }
}
