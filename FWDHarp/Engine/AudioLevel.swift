import Foundation
import CoreGraphics

// Copied from FWD Sequencer (PlaybackMonitor.swift) on 2026-11-20.

/// One meter reading: both the true peak and the RMS of a buffer, in linear terms.
///
/// Peak is what decides clipping — RMS alone cannot show an over, which is why the
/// old single RMS value made it impossible to mix to 0 dBFS.
nonisolated struct AudioLevel: Equatable {
    var peak: Float = 0
    var rms: Float = 0

    static let silent = AudioLevel()

    /// Full scale is 0 dBFS; silence is -infinity.
    var peakDB: Float { peak > 0 ? 20 * log10(peak) : -.infinity }
    var rmsDB: Float { rms > 0 ? 20 * log10(rms) : -.infinity }

    /// A sample reached or passed full scale, so the signal is clipping.
    var isOver: Bool { peak >= 1.0 }

    /// Where a dB value sits on a meter scaled from `floorDB` to 0 dBFS.
    /// Mixing decisions live between about -30 and 0 dBFS; on the old linear scale
    /// that was squashed into the bottom few percent of the bar.
    static let floorDB: Float = -60
    static func fraction(ofDB db: Float) -> CGFloat {
        guard db.isFinite else { return 0 }
        return CGFloat(min(1, max(0, (db - floorDB) / -floorDB)))
    }
    var peakFraction: CGFloat { Self.fraction(ofDB: peakDB) }
    var rmsFraction: CGFloat { Self.fraction(ofDB: rmsDB) }
}
