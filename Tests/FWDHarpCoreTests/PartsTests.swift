import XCTest
@testable import FWDHarpCore

/// Two parts (plate and auto-strum) and the mixer, in the saved setup.
final class PartsTests: XCTestCase {
    private let synth = PluginInfo(name: "Synth", manufacturerName: "Maker",
                                   componentType: 1, componentSubType: 2, componentManufacturer: 3)

    func testASetupFromBeforePartsOpensUnchanged() throws {
        let old = Data(#"{"builtInSound": 10, "keyTonic": 7}"#.utf8)
        let setup = try SetupStorage.decode(old)
        XCTAssertEqual(setup.plateSound.builtInSound, 10, "the plate keeps the one instrument")
        XCTAssertNil(setup.autoSound, "auto-strum plays through the plate")
        XCTAssertEqual(setup.plateMix, ChannelMix())
        XCTAssertEqual(setup.masterVolume, 1)
    }

    func testAutoStrumsOwnSoundAndTheMixerAreSaved() throws {
        var setup = HarpSetup()
        setup.autoSound = PartSound(instrument: synth, instrumentState: Data([9]), builtInSound: 24)
        setup.autoMix = ChannelMix(volume: 0.5, pan: -0.4, muted: true)
        setup.masterVolume = 1.5
        let back = try SetupStorage.decode(JSONEncoder().encode(setup))
        XCTAssertEqual(back.autoSound?.instrument, synth)
        XCTAssertEqual(back.autoSound?.instrumentState, Data([9]))
        XCTAssertEqual(back.autoMix, ChannelMix(volume: 0.5, pan: -0.4, muted: true))
        XCTAssertEqual(back.masterVolume, 1.5)
    }

    func testPlateSoundReadsAndWritesThePlateFields() {
        var setup = HarpSetup()
        var sound = setup.plateSound
        sound.instrument = synth
        sound.builtInSound = 5
        setup.setSound(sound, for: .plate)
        XCTAssertEqual(setup.instrument, synth)
        XCTAssertEqual(setup.builtInSound, 5)
        XCTAssertEqual(setup.sound(of: .plate), sound)
        XCTAssertNil(setup.sound(of: .auto))
    }

    func testMixerValuesAreKeptInRange() throws {
        let data = Data(#"{"plateMix": {"volume": 9, "pan": -3}, "masterVolume": -1, "autoSound": {"builtInSound": 900}}"#.utf8)
        let setup = try SetupStorage.decode(data)
        XCTAssertEqual(setup.plateMix.volume, ChannelMix.maximumVolume)
        XCTAssertEqual(setup.plateMix.pan, -1)
        XCTAssertEqual(setup.masterVolume, 0)
        XCTAssertEqual(setup.autoSound?.builtInSound, HarpSetup.defaultBuiltInSound)
    }

    func testMuteSilencesWithoutLosingTheLevel() {
        var mix = ChannelMix(volume: 0.7)
        mix.muted = true
        XCTAssertEqual(mix.effectiveVolume, 0)
        XCTAssertEqual(mix.volume, 0.7, "unmuting brings the level back")
    }
}

final class PlateRingTests: XCTestCase {
    func testRingTimes() {
        XCTAssertEqual(PlateRing.short.seconds, 0.4)
        XCTAssertEqual(PlateRing.long.seconds, 3)
        XCTAssertNil(PlateRing.untilChordChange.seconds, "the old behaviour, kept as a choice")
        XCTAssertNil(PlateRing.whileHeld.seconds, "released by the finger, like a keyboard")
    }

    func testRingIsSavedAndStartsWhileHeld() throws {
        XCTAssertEqual(try SetupStorage.decode(Data("{}".utf8)).plateRing, .whileHeld)
        var setup = HarpSetup()
        setup.plateRing = .short
        XCTAssertEqual(try SetupStorage.decode(JSONEncoder().encode(setup)).plateRing, .short)
    }
}

/// The strum plate's slide (2026-11-23).
final class PlateSlideTests: XCTestCase {
    func testNothingMovesWhereTheFingerLands() {
        XCTAssertEqual(PlateSlide.expression.message(slide: 0, depth: .medium)?.data2, PlateSlide.landingExpression)
        XCTAssertEqual(PlateSlide.modWheel.message(slide: 0, depth: .medium)?.data2, 0)
        let bend = PlateSlide.pitchBend.message(slide: 0, depth: .strong)!
        XCTAssertEqual(Int(bend.data1) | Int(bend.data2) << 7, 8192, "no bend")
        XCTAssertNil(PlateSlide.off.message(slide: 0.5, depth: .medium))
    }

    func testASmallWobbleIsHeard() {
        // A tenth of the plate (about 30 points): enough to hear at Medium.
        let right = PlateSlide.expression.message(slide: 0.1, depth: .medium)!
        let left = PlateSlide.expression.message(slide: -0.1, depth: .medium)!
        XCTAssertEqual(right.status, 0xB0)
        XCTAssertEqual(right.data1, 11)
        XCTAssertGreaterThanOrEqual(Int(right.data2) - Int(left.data2), 50)
        XCTAssertEqual(PlateSlide.modWheel.message(slide: -0.2, depth: .medium)?.data2, 60, "either way adds")
        XCTAssertEqual(PlateSlide.aftertouch.message(slide: 0.2, depth: .medium)?.status, 0xD0)
        let up = PlateSlide.pitchBend.message(slide: 0.1, depth: .medium)!
        XCTAssertEqual(up.status, 0xE0)
        XCTAssertEqual(Int(up.data1) | Int(up.data2) << 7, 8992)
        let full = PlateSlide.pitchBend.message(slide: 1, depth: .strong)!
        XCTAssertEqual(Int(full.data1) | Int(full.data2) << 7, 16383, "held to the top")
    }

    func testResetsAndSaving() throws {
        XCTAssertEqual(PlateSlide.expression.reset?.data2, 127)
        XCTAssertEqual(PlateSlide.pitchBend.reset.map { Int($0.data1) | Int($0.data2) << 7 }, 8192)
        var setup = HarpSetup()
        XCTAssertEqual(setup.plateSlide, .expression)
        setup.plateSlide = .pitchBend
        setup.slideDepth = .strong
        let back = try SetupStorage.decode(JSONEncoder().encode(setup))
        XCTAssertEqual(back.plateSlide, .pitchBend)
        XCTAssertEqual(back.slideDepth, .strong)
    }
}
