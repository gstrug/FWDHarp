import XCTest
@testable import FWDHarpCore

/// Saving the setup: backups, quarantine, and files from other versions.
final class SetupStorageTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FWDHarpTests-\(UUID().uuidString)", isDirectory: true)
        SetupStorage.directoryOverrideForTesting = folder
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        SetupStorage.directoryOverrideForTesting = nil
        super.tearDown()
    }

    private func sampleSetup() -> HarpSetup {
        var setup = HarpSetup()
        setup.instrument = PluginInfo(name: "Synth", manufacturerName: "Maker",
                                      componentType: 1, componentSubType: 2, componentManufacturer: 3)
        setup.instrumentState = Data([1, 2, 3])
        setup.builtInSound = 24
        setup.effects = [PluginSlot(pluginInfo: PluginInfo(name: "Reverb", manufacturerName: "Maker",
                                                           componentType: 4, componentSubType: 5,
                                                           componentManufacturer: 6),
                                    isBypassed: true)]
        return setup
    }

    func testAFirstLaunchStartsFresh() {
        XCTAssertEqual(SetupStorage.load(), .fresh)
    }

    func testASavedSetupComesBack() {
        let setup = sampleSetup()
        XCTAssertNoThrow(try SetupStorage.save(setup).get())
        XCTAssertEqual(SetupStorage.load(), .loaded(setup))
    }

    func testTheSecondSaveKeepsTheFirstAsTheBackup() throws {
        var setup = sampleSetup()
        try SetupStorage.save(setup).get()
        setup.builtInSound = 0
        try SetupStorage.save(setup).get()
        let backup = try SetupStorage.decode(Data(contentsOf: SetupStorage.backupURL))
        XCTAssertEqual(backup.builtInSound, 24)
    }

    func testADamagedFileIsKeptAsideAndTheBackupUsed() throws {
        var setup = sampleSetup()
        try SetupStorage.save(setup).get()
        setup.builtInSound = 0
        try SetupStorage.save(setup).get()       // the backup now holds sound 24
        try Data("not a setup".utf8).write(to: SetupStorage.fileURL)

        guard case .restoredFromBackup(let restored) = SetupStorage.load() else {
            return XCTFail("the backup should have been used")
        }
        XCTAssertEqual(restored.builtInSound, 24)
        XCTAssertNotNil(SetupLoadResult.restoredFromBackup(restored).notice)
        let kept = try FileManager.default.contentsOfDirectory(atPath: SetupStorage.quarantineDirectory.path)
        XCTAssertEqual(kept.count, 1, "the damaged file is kept, never deleted")
        // The backup was put back in place, so the next launch opens it directly.
        XCTAssertEqual(SetupStorage.load(), .loaded(restored))
    }

    func testADamagedFileWithNoBackupStartsFreshAndKeepsTheFile() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not a setup".utf8).write(to: SetupStorage.fileURL)
        XCTAssertEqual(SetupStorage.load(), .unreadable)
        XCTAssertNotNil(SetupLoadResult.unreadable.notice)
        let kept = try FileManager.default.contentsOfDirectory(atPath: SetupStorage.quarantineDirectory.path)
        XCTAssertEqual(kept.count, 1)
    }

    func testADamagedFileNeverReplacesTheGoodBackup() throws {
        try SetupStorage.save(sampleSetup()).get()
        try SetupStorage.save(sampleSetup()).get()   // backup exists and is good
        try Data("not a setup".utf8).write(to: SetupStorage.fileURL)
        var next = sampleSetup()
        next.builtInSound = 99
        try SetupStorage.save(next).get()
        let backup = try SetupStorage.decode(Data(contentsOf: SetupStorage.backupURL))
        XCTAssertEqual(backup.builtInSound, 24, "the damaged file was not promoted to backup")
    }

    func testAFileWithMissingOrUnknownSettingsStillOpens() throws {
        let data = Data(#"{"builtInSound": 10, "somethingFromALaterVersion": true}"#.utf8)
        let setup = try SetupStorage.decode(data)
        XCTAssertEqual(setup.builtInSound, 10)
        XCTAssertNil(setup.instrument)
        XCTAssertEqual(setup.effects, [])
    }

    func testOutOfRangeValuesArePutRight() throws {
        let data = Data(#"{"builtInSound": 500, "instrumentState": "AQID"}"#.utf8)
        let setup = try SetupStorage.decode(data)
        XCTAssertEqual(setup.builtInSound, HarpSetup.defaultBuiltInSound)
        XCTAssertNil(setup.instrumentState, "a patch with no instrument is dropped")
    }

    func testEffectSilencing() {
        var setup = sampleSetup()
        XCTAssertTrue(setup.effectIsSilenced(at: 0), "bypassed itself")
        setup.effects[0].isBypassed = nil
        XCTAssertFalse(setup.effectIsSilenced(at: 0))
        setup.effectsBypassed = true
        XCTAssertTrue(setup.effectIsSilenced(at: 0), "the whole chain is out")
    }
}

/// Decoding incoming MIDI, copied with FWD Sequencer's tests.
final class MIDIMessageTests: XCTestCase {
    func testDecodesControlChangeOnChannelOne() {
        let m = MIDIControlMessage(status: 0xB0, data1: 7, data2: 100)
        XCTAssertEqual(m, MIDIControlMessage(kind: .controlChange, channel: 1, number: 7, value: 100))
    }

    func testDecodesNotesAndTreatsVelocityZeroAsRelease() {
        let on = MIDIControlMessage(status: 0x99, data1: 36, data2: 90)!
        XCTAssertEqual(on.kind, .note)
        XCTAssertEqual(on.channel, 10)
        XCTAssertTrue(on.isPress)

        XCTAssertFalse(MIDIControlMessage(status: 0x99, data1: 36, data2: 0)!.isPress)
        let off = MIDIControlMessage(status: 0x89, data1: 36, data2: 64)!
        XCTAssertEqual(off.value, 0, "a note off is a release whatever its velocity byte")
        XCTAssertFalse(off.isPress)
    }

    func testIgnoresMessagesThatAreNotNotesOrControllers() {
        XCTAssertNil(MIDIControlMessage(status: 0xE0, data1: 0, data2: 64))  // pitch bend
        XCTAssertNil(MIDIControlMessage(status: 0xC0, data1: 5, data2: 0))   // program change
        XCTAssertNil(MIDIControlMessage(status: 0xF8, data1: 0, data2: 0))   // clock
    }
}
