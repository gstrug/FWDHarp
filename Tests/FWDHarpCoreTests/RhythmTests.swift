import XCTest
@testable import FWDHarpCore

/// The rhythm section's patterns, its bass, and how it is saved.
final class RhythmTests: XCTestCase {
    private func allBars(_ style: RhythmStyle) -> [(String, RhythmBar)] {
        [("A", style.bar(.a)), ("B", style.bar(.b)), ("fill", style.fill), ("intro", style.intro)]
    }

    func testEveryLineFillsTheBar() {
        for style in RhythmStyle.allCases {
            for (name, bar) in allBars(style) {
                for (voice, line) in bar.drums {
                    XCTAssertEqual(line.count, style.stepsPerBar, "\(style) \(name) \(voice)")
                    XCTAssertTrue(line.allSatisfy { $0 == "." || RhythmBar.velocity($0) != nil },
                                  "\(style) \(name) \(voice): \(line)")
                }
                if !bar.bass.isEmpty {
                    XCTAssertEqual(bar.bass.count, style.stepsPerBar, "\(style) \(name) bass")
                    XCTAssertTrue(bar.bass.allSatisfy { "R5LO367.-".contains($0) }, "\(style) \(name) bass")
                    XCTAssertNotEqual(bar.bass.first, "-", "\(style) \(name): a tie needs a note before it")
                }
            }
            XCTAssertFalse(style.bar(.a).bass.isEmpty, "\(style) A has a bass line")
            XCTAssertFalse(style.bar(.b).bass.isEmpty, "\(style) B has a bass line")
            XCTAssertNotEqual(style.bar(.a), style.bar(.b), "\(style): B is a variation")
        }
    }

    func testMetres() {
        XCTAssertEqual(RhythmStyle.waltz.stepsPerBar, 12, "3/4 in sixteenths")
        XCTAssertEqual(RhythmStyle.bluesShuffle.stepsPerBar, 12, "4/4 in triplets")
        XCTAssertTrue(RhythmStyle.bluesShuffle.swings)
        XCTAssertFalse(RhythmStyle.rock.swings)
        XCTAssertEqual(RhythmStyle.rock.stepsPerBar, 16)
    }

    func testHitsAndBassLengths() {
        let bar = RhythmBar(drums: [.kick: "x...", .snare: "X.g."], bass: "R--5")
        let first = bar.hits(at: 0)
        XCTAssertEqual(first.map(\.note), [DrumVoice.snare.note, DrumVoice.kick.note], "loudest first")
        XCTAssertEqual(bar.hits(at: 2).map(\.velocity), [40])
        XCTAssertTrue(bar.hits(at: 1).isEmpty)
        XCTAssertEqual(bar.bassNote(at: 0)?.degree, "R")
        XCTAssertEqual(bar.bassNote(at: 0)?.steps, 3, "held through the ties")
        XCTAssertNil(bar.bassNote(at: 1), "a tie starts nothing")
        XCTAssertEqual(bar.bassNote(at: 3)?.steps, 1)
        XCTAssertNil(bar.bassNote(at: 9))
    }

    func testBassFollowsTheChord() {
        let c = Chord(root: 0, quality: .major)
        let am = Chord(root: 9, quality: .minor)
        let e = Chord(root: 4, quality: .major)
        let eFlat = Chord(root: 3, quality: .major)
        XCTAssertEqual(RhythmBass.root(of: e), 28, "E1, the bass's lowest string")
        XCTAssertEqual(RhythmBass.root(of: eFlat), 39, "below E goes up an octave")
        XCTAssertEqual(RhythmBass.root(of: c), 36)
        XCTAssertEqual(RhythmBass.note("5", over: c), 43)
        XCTAssertEqual(RhythmBass.note("O", over: c), 48)
        XCTAssertEqual(RhythmBass.note("L", over: c), 31)
        XCTAssertEqual(RhythmBass.note("3", over: c), 40, "major third")
        XCTAssertEqual(RhythmBass.note("3", over: am), RhythmBass.root(of: am) + 3, "minor third")
        XCTAssertEqual(RhythmBass.note("3", over: Chord(root: 0, quality: .suspendedFourth)), 41, "sus4's 4th")
        XCTAssertEqual(RhythmBass.note("7", over: c), 46, "flat seventh by default")
        XCTAssertNil(RhythmBass.note(".", over: c))
    }

    func testDrumsAndBassAreParts() throws {
        XCTAssertEqual(HarpPart.allCases, [.plate, .auto, .drums, .bass])
        let setup = try SetupStorage.decode(Data("{}".utf8))
        XCTAssertEqual(setup.sound(of: .drums)?.builtInSound, GeneralMIDI.drumKit)
        XCTAssertEqual(setup.sound(of: .bass)?.builtInSound, PartSound.defaultBassBuiltInSound)
        XCTAssertEqual(setup.midiOut.channel(for: .drums), 10, "General MIDI's drum channel")
        XCTAssertEqual(setup.midiOut.channel(for: .bass), 3)
        XCTAssertEqual(setup.rhythmStyle, .rock)
        XCTAssertEqual(setup.rhythmVariation, .a)
        XCTAssertFalse(setup.rhythmIntro)
    }

    func testRhythmSettingsAreSaved() throws {
        var setup = HarpSetup()
        setup.rhythmStyle = .bossa
        setup.rhythmVariation = .b
        setup.rhythmIntro = true
        var mix = setup.mix(of: .bass)
        mix.volume = 0.5
        setup.setMix(mix, for: .bass)
        setup.setSound(PartSound(builtInSound: 38), for: .bass)
        setup.midiOut.setChannel(11, for: .drums)
        setup.midiOut.setPlaysOwnSound(false, for: .bass)
        let back = try SetupStorage.decode(JSONEncoder().encode(setup))
        XCTAssertEqual(back.rhythmStyle, .bossa)
        XCTAssertEqual(back.rhythmVariation, .b)
        XCTAssertTrue(back.rhythmIntro)
        XCTAssertEqual(back.mix(of: .bass).volume, 0.5)
        XCTAssertEqual(back.sound(of: .bass)?.builtInSound, 38)
        XCTAssertEqual(back.midiOut.channel(for: .drums), 11)
        XCTAssertFalse(back.midiOut.playsOwnSound(.bass))
        XCTAssertTrue(back.midiOut.playsOwnSound(.drums))
        // A style from a later version falls back rather than losing the setup.
        let later = try SetupStorage.decode(Data(#"{"rhythmStyle": "polka"}"#.utf8))
        XCTAssertEqual(later.rhythmStyle, .rock)
    }
}
