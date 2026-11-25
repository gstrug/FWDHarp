import Foundation
import Combine

/// FWD Harp's sound: a part for the plate and one for auto-strum (HarpPart), each with
/// an instrument (the built-in General MIDI sound or a hosted AUv3), its effects and a
/// mixer channel. Auto-strum plays through the plate's instrument until it is given one
/// of its own. With FWD Sequencer's load protection (generation-tokened loads, a 30 s
/// time limit with the built-in sound as fallback, a blocking overlay while loading)
/// and its saving (SetupStorage: backups and quarantine).
///
/// Plugin state is captured only at safe moments — an editor closing, the app going to
/// the background — and only for an instrument whose sound may have changed (FWD
/// lesson 3), so a plugin that ignored its restore never has its default saved over the
/// user's patch.
final class InstrumentStore: ObservableObject {
    /// The engine keys everything by a track id, as in FWD: one per part. The plate
    /// keeps the id the single instrument had.
    static func trackID(for part: HarpPart) -> UUID {
        switch part {
        case .plate: return UUID(uuidString: "6E0A7C8E-3B1F-4D5A-9C2E-0000000000A1")!
        case .auto: return UUID(uuidString: "6E0A7C8E-3B1F-4D5A-9C2E-0000000000A2")!
        case .drums: return UUID(uuidString: "6E0A7C8E-3B1F-4D5A-9C2E-0000000000A3")!
        case .bass: return UUID(uuidString: "6E0A7C8E-3B1F-4D5A-9C2E-0000000000A4")!
        }
    }

    @Published private(set) var setup = HarpSetup() {
        didSet { if setup != oldValue { scheduleSave() } }
    }
    /// True while an instrument loads; the screen is blocked until it is ready
    /// (FWD lesson 1: interrupting a fragile AUv3 while it loads crashes it).
    @Published private(set) var isLoading = false
    @Published private(set) var loadingName: String?
    @Published var notice: String?
    /// The meters, kept apart so their 20-a-second updates redraw only the meters.
    let levels: LevelMonitor

    let engine = AudioEngineManager.shared
    /// Every note of the plate and auto-strum goes through here: to its instrument,
    /// and MIDI out on its channel.
    let router: NoteRouter
    private var loads = PluginLoadTracker()
    private var saveWorkItem: DispatchWorkItem?
    /// Writes happen here, off the main thread, from a copy of the setup: saving never
    /// touches the live document (FWD lesson 4).
    private let saveQueue = DispatchQueue(label: "com.fwdharp.setup-save", qos: .utility)
    private let levelBatcher: LevelBatcher

    init() {
        let loaded = SetupStorage.load()
        switch loaded {
        case .loaded(let saved), .restoredFromBackup(let saved): setup = saved
        case .fresh, .unreadable: break
        }
        let levels = LevelMonitor()
        self.levels = levels
        router = NoteRouter(engine: AudioEngineManager.shared)
        levelBatcher = LevelBatcher { tracks, master in
            if !tracks.isEmpty {
                var merged = levels.trackLevels
                for (id, level) in tracks { merged[id] = level }
                if merged != levels.trackLevels { levels.trackLevels = merged }
            }
            if let master, master != levels.masterLevel { levels.masterLevel = master }
        }
        notice = loaded.notice
        // Not a change: assigning the loaded setup must not write it straight back.
        saveWorkItem?.cancel()
        saveWorkItem = nil

        engine.onStatusChange = { [weak self] status in
            if case .failed(let message) = status { self?.notice = message }
        }
        engine.onEffectRefused = { [weak self] name in
            self?.notice = "\(name) could not be connected, so it has been left out and the part plays without it. It may need audio this app can't give it; try another effect, or remove it."
        }
        engine.onPlaybackInterrupted = { [weak self] _ in
            guard let self else { return }
            let engine = engine
            router.afterQueued { engine.allNotesOff() }
        }
        // The audio system restarted and every node was thrown away: build the parts
        // again, with their saved sounds.
        engine.onRecoveryRequired = { [weak self] in
            self?.buildParts()
        }
        // Only the batcher is captured: these run on the audio thread.
        let batcher = levelBatcher
        engine.onLevelUpdate = { id, level in batcher.track(id, level) }
        engine.onMasterLevelUpdate = { level in batcher.master(level) }
        buildParts()
        router.setSettings(setup.midiOut)
        updateRoutes()
    }

    /// Tell the router which engine track each part sounds on.
    private func updateRoutes() {
        for part in HarpPart.allCases { router.setTrack(soundingTrackID(for: part), for: part) }
    }

    /// Put each part's instrument, effects and mixer settings into the engine.
    private func buildParts() {
        loads.cancelAll()
        isLoading = false
        loadingName = nil
        for part in HarpPart.allCases { buildPart(part) }
        engine.setMasterVolume(setup.masterVolume)
    }

    private func buildPart(_ part: HarpPart) {
        guard let sound = setup.sound(of: part) else { return }
        let id = Self.trackID(for: part)
        let mix = setup.mix(of: part)
        engine.addTrack(id: id, volume: mix.effectiveVolume, pan: mix.pan, builtInSound: sound.builtInSound)
        engine.setVolume(mix.effectiveVolume, for: id)
        engine.setPan(mix.pan, for: id)
        if let plugin = sound.instrument {
            load(plugin, state: sound.instrumentState, for: part)
        }
        loadEffects(for: part)
    }

    // MARK: - Parts

    /// Whether a part has a sound of its own. Auto-strum without one plays through the
    /// plate's instrument.
    func hasOwnSound(_ part: HarpPart) -> Bool { setup.sound(of: part) != nil }

    /// The track a part's notes go to: its own, or the plate's for auto-strum without
    /// a sound of its own.
    func soundingTrackID(for part: HarpPart) -> UUID {
        hasOwnSound(part) ? Self.trackID(for: part) : Self.trackID(for: .plate)
    }

    func plugin(for part: HarpPart) -> PluginInfo? { setup.sound(of: part)?.instrument }
    func builtInSound(for part: HarpPart) -> Int {
        setup.sound(of: part)?.builtInSound ?? setup.builtInSound
    }
    func effects(for part: HarpPart) -> [PluginSlot] { setup.sound(of: part)?.effects ?? [] }
    func effectsBypassed(for part: HarpPart) -> Bool { setup.sound(of: part)?.effectsBypassed ?? false }

    func instrumentName(for part: HarpPart) -> String {
        guard let sound = setup.sound(of: part) else { return "Same as Plate" }
        return sound.instrument?.name ?? GeneralMIDI.soundName(sound.builtInSound)
    }

    /// Give auto-strum a sound of its own (starting on a built-in nylon guitar), or
    /// send it back through the plate's instrument.
    func setAutoHasOwnSound(_ own: Bool) {
        guard own != hasOwnSound(.auto) else { return }
        if own {
            setup.autoSound = PartSound(builtInSound: PartSound.defaultAutoBuiltInSound)
            buildPart(.auto)
        } else {
            let id = Self.trackID(for: .auto)
            engine.removeTrack(id: id)
            loads.cancel(for: id)
            isLoading = !loads.isEmpty
            setup.autoSound = nil
        }
        updateRoutes()
    }

    private func updateSound(of part: HarpPart, _ change: (inout PartSound) -> Void) {
        guard var sound = setup.sound(of: part) else { return }
        change(&sound)
        setup.setSound(sound, for: part)
    }

    // MARK: - Instrument

    /// Choose a part's instrument: a plugin, or nil for the built-in sound. Choosing the
    /// one already playing loads it again, which is how a plugin that timed out is
    /// retried.
    func choose(_ newPlugin: PluginInfo?, for part: HarpPart) {
        guard let sound = setup.sound(of: part) else { return }
        guard newPlugin != nil || sound.instrument != nil else { return }
        if newPlugin == sound.instrument, let newPlugin {
            // Same plugin again: reload with its saved patch, not a blank one.
            load(newPlugin, state: sound.instrumentState, for: part)
            return
        }
        updateSound(of: part) {
            $0.instrument = newPlugin
            $0.instrumentState = nil   // a fresh plugin starts on its own default sound
        }
        load(newPlugin, state: nil, for: part)
    }

    /// Load a part's instrument again, for a plugin whose window came up blank.
    func reload(_ part: HarpPart) {
        guard let sound = setup.sound(of: part) else { return }
        load(sound.instrument, state: sound.instrumentState, for: part)
    }

    func setBuiltInSound(_ sound: Int, for part: HarpPart) {
        updateSound(of: part) { $0.builtInSound = sound }
        engine.setBuiltInSound(sound, for: Self.trackID(for: part))
    }

    /// A part's instrument editor closed: keep its sound.
    func captureInstrumentState(for part: HarpPart) {
        guard !isLoading, plugin(for: part) != nil else { return }
        let current = setup.sound(of: part)?.instrumentState
        if let state = engine.captureState(for: Self.trackID(for: part)), state != current {
            updateSound(of: part) { $0.instrumentState = state }
        }
    }

    private func load(_ info: PluginInfo?, state: Data?, for part: HarpPart) {
        let id = Self.trackID(for: part)
        let token = loads.begin(for: id)
        loadingName = info?.name ?? "Built-in sound"
        isLoading = true
        engine.loadPlugin(info, for: id, stateData: state) { [weak self] result in
            guard let self else { return }
            guard loads.finish(for: id, token: token) else { return }
            isLoading = !loads.isEmpty
            if !isLoading { loadingName = nil }
            switch result {
            case .success, .failure(.cancelled):
                break
            case .failure(let error):
                notice = error.localizedDescription
            }
        }
    }

    // MARK: - Settings

    func setKey(_ key: MusicKey) {
        setup.keyTonic = key.tonic
        setup.keyMinor = key.isMinor
    }

    func setPlateStrings(_ strings: Int) {
        guard StrumPlate.stringChoices.contains(strings) else { return }
        setup.plateStrings = strings
    }

    func setPlateScale(_ scale: PlateScale) {
        setup.plateScale = scale
    }

    func setPlateRing(_ ring: PlateRing) {
        setup.plateRing = ring
    }

    func setPlatePattern(_ pattern: PlatePattern) {
        setup.platePattern = pattern
    }

    func setAutoStrumPattern(_ pattern: AutoStrumPattern) {
        setup.autoStrumPattern = pattern
    }

    func setTempo(_ tempo: Double) {
        setup.tempo = min(max(tempo.rounded(), AutoStrum.tempoRange.lowerBound), AutoStrum.tempoRange.upperBound)
    }

    func setRhythmStyle(_ style: RhythmStyle) { setup.rhythmStyle = style }
    func setPlateSlide(_ slide: PlateSlide) { setup.plateSlide = slide }
    func setSlideDepth(_ depth: SlideDepth) { setup.slideDepth = depth }
    func setRhythmVariation(_ variation: RhythmVariation) { setup.rhythmVariation = variation }

    func setOctaveShift(_ shift: Int) {
        setup.octaveShift = min(max(shift, StrumPlate.octaveShiftRange.lowerBound),
                                StrumPlate.octaveShiftRange.upperBound)
    }

    // MARK: - Mixer

    func setVolume(_ volume: Float, for part: HarpPart) {
        var mix = setup.mix(of: part)
        mix.volume = ChannelMix.clampVolume(volume, default: mix.volume)
        setup.setMix(mix, for: part)
        engine.setVolume(mix.effectiveVolume, for: Self.trackID(for: part))
    }

    func setPan(_ pan: Float, for part: HarpPart) {
        var mix = setup.mix(of: part)
        mix.pan = min(max(pan, -1), 1)
        setup.setMix(mix, for: part)
        engine.setPan(mix.pan, for: Self.trackID(for: part))
    }

    func setMuted(_ muted: Bool, for part: HarpPart) {
        var mix = setup.mix(of: part)
        mix.muted = muted
        setup.setMix(mix, for: part)
        engine.setVolume(mix.effectiveVolume, for: Self.trackID(for: part))
    }

    func setMasterVolume(_ volume: Float) {
        setup.masterVolume = ChannelMix.clampVolume(volume, default: setup.masterVolume)
        engine.setMasterVolume(setup.masterVolume)
    }

    // MARK: - Notes

    /// The plate's notes, from hand strumming: to its instrument and MIDI out.
    /// Meters measure only while the mixer is open; closed, they are cleared so they
    /// open again from silence rather than showing an old level.
    func setMetersShown(_ shown: Bool) {
        engine.metersShown = shown
        if !shown {
            levels.trackLevels = [:]
            levels.masterLevel = .silent
        }
    }

    func noteOn(_ note: UInt8, velocity: UInt8 = 100) {
        router.play(.plate, note: note, velocity: velocity)
    }

    func noteOff(_ note: UInt8) {
        router.stop(.plate, note: note)
    }

    // MARK: - MIDI out

    var midiOut: MIDIOutSettings { setup.midiOut }

    func setMIDIOut(_ settings: MIDIOutSettings) {
        let before = setup.midiOut
        setup.midiOut = settings.normalized()
        router.setSettings(setup.midiOut)
        // A part's own sound switched off: silence what its instrument is playing.
        if HarpPart.allCases.contains(where: { before.playsOwnSound($0) && !setup.midiOut.playsOwnSound($0) }) {
            let engine = engine
            router.afterQueued { engine.allNotesOff() }
        }
    }

    /// A MIDI keyboard plays the plate's instrument directly: its notes, sustain pedal,
    /// mod wheel, pitch bend and aftertouch. Runs on CoreMIDI's thread and goes straight
    /// to the engine, which is thread-safe and drops MIDI while a plugin loads. Keys and
    /// controllers a MIDI Learn link uses control the app instead (`gate` says which),
    /// and every message is also handed to `forward`, for links and activity lights.
    /// Started by MIDIControlCenter, which starts the input.
    func startMIDIInput(gate: MIDIInputGate,
                        forward: @escaping @Sendable (MIDIInputManager.Source, MIDIControlMessage) -> Void) {
        let engine = engine
        let part = Self.trackID(for: .plate)
        let input = MIDIInputManager.shared
        input.onMessage = { @Sendable source, message in
            forward(source, message)
            guard gate.playsPlate(device: source.name, message) else { return }
            switch message.kind {
            case .note:
                let note = UInt8(message.number)
                if message.value > 0 {
                    engine.playNote(trackID: part, midiNote: note, velocity: UInt8(message.value))
                } else {
                    engine.stopNote(trackID: part, midiNote: note)
                }
            case .controlChange:
                engine.sendPerformanceMessage(trackID: part, status: 0xB0,
                                              data1: UInt8(message.number), data2: UInt8(message.value))
            }
        }
        input.onPerformanceMessage = { @Sendable source, status, data1, data2 in
            guard gate.playsPerformance(device: source.name) else { return }
            engine.sendPerformanceMessage(trackID: part, status: status, data1: data1, data2: data2)
        }
    }

    // MARK: - Effects (as FWD Sequencer's SongStore)

    private func loadEffects(for part: HarpPart) {
        guard let sound = setup.sound(of: part) else { return }
        let id = Self.trackID(for: part)
        for (index, slot) in sound.effects.enumerated() {
            // Bypass goes in with the load: loading is asynchronous, so setting it
            // afterwards would set it on a chain the effect has not joined yet.
            engine.loadEffect(slot.pluginInfo, at: index, for: id,
                              stateData: slot.stateData,
                              bypassed: sound.effectIsSilenced(at: index)) { [weak self] result in
                guard case .failure(let error) = result else { return }
                self?.notice = error.localizedDescription
            }
        }
    }

    func addEffect(_ info: PluginInfo, to part: HarpPart) {
        guard let sound = setup.sound(of: part) else { return }
        guard sound.effects.count < HarpSetup.maximumEffects else {
            notice = "Up to \(HarpSetup.maximumEffects) effects can be added."
            return
        }
        let position = sound.effects.count
        updateSound(of: part) { $0.effects.append(PluginSlot(pluginInfo: info)) }
        // Joins switched out if the chain is switched out.
        engine.loadEffect(info, at: position, for: Self.trackID(for: part),
                          bypassed: sound.effectsBypassed) { [weak self] result in
            guard case .failure(let error) = result else { return }
            self?.notice = error.localizedDescription
        }
    }

    /// Order is signal order. The identical move is applied to the setup and to the
    /// units, which keeps them in step.
    func moveEffects(from source: IndexSet, to destination: Int, for part: HarpPart) {
        guard !effects(for: part).isEmpty else { return }
        updateSound(of: part) { sound in
            var slots = sound.effects
            let moving = source.sorted().compactMap { slots.indices.contains($0) ? slots[$0] : nil }
            slots = slots.enumerated().filter { !source.contains($0.offset) }.map(\.element)
            let insertAt = destination - source.filter { $0 < destination }.count
            slots.insert(contentsOf: moving, at: min(max(0, insertAt), slots.count))
            sound.effects = slots
        }
        engine.moveEffect(from: source, to: destination, for: Self.trackID(for: part))
    }

    /// Swap one effect for another in the same place. The new one starts fresh and in
    /// circuit, since you are swapping it in to hear it.
    func replaceEffect(at index: Int, with info: PluginInfo, for part: HarpPart) {
        let slots = effects(for: part)
        guard slots.indices.contains(index), slots[index].pluginInfo != info else { return }
        updateSound(of: part) { $0.effects[index] = PluginSlot(pluginInfo: info) }
        let id = Self.trackID(for: part)
        engine.removeEffect(at: index, for: id)
        engine.loadEffect(info, at: index, for: id,
                          bypassed: effectsBypassed(for: part)) { [weak self] result in
            guard case .failure(let error) = result else { return }
            self?.notice = error.localizedDescription
        }
    }

    func removeEffect(at index: Int, from part: HarpPart) {
        guard effects(for: part).indices.contains(index) else { return }
        updateSound(of: part) { $0.effects.remove(at: index) }
        engine.removeEffect(at: index, for: Self.trackID(for: part))
    }

    func setEffectBypassed(_ bypassed: Bool, at index: Int, for part: HarpPart) {
        guard effects(for: part).indices.contains(index) else { return }
        updateSound(of: part) { $0.effects[index].isBypassed = bypassed ? true : nil }
        // While the chain is switched out the effect stays silent; its own setting is
        // still kept, and takes effect when the chain comes back in.
        guard let sound = setup.sound(of: part) else { return }
        engine.setEffectBypassed(sound.effectIsSilenced(at: index), at: index, for: Self.trackID(for: part))
    }

    func setEffectsChainBypassed(_ bypassed: Bool, for part: HarpPart) {
        updateSound(of: part) { $0.effectsBypassed = bypassed }
        guard let sound = setup.sound(of: part) else { return }
        for index in sound.effects.indices {
            engine.setEffectBypassed(sound.effectIsSilenced(at: index), at: index, for: Self.trackID(for: part))
        }
    }

    /// An effect's editor closed: keep its settings.
    func captureEffectState(at index: Int, for part: HarpPart) {
        guard effects(for: part).indices.contains(index),
              let state = engine.captureEffectState(at: index, for: Self.trackID(for: part)) else { return }
        updateSound(of: part) { $0.effects[index].stateData = state }
    }

    // MARK: - Saving

    /// A safe moment (the app going to the background): capture each instrument whose
    /// sound may have changed, then save at once.
    func captureAndSave() {
        for part in HarpPart.allCases where hasOwnSound(part)
            && engine.mayHaveNewState(Self.trackID(for: part)) {
            captureInstrumentState(for: part)
        }
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let snapshot = setup
        // On the save queue, so it can never overlap a debounced save already writing;
        // waited for, because the app may be suspended straight after.
        let result = saveQueue.sync { SetupStorage.save(snapshot) }
        if case .failure(let error) = result { notice = error.localizedDescription }
    }

    /// One second after the last change, off the main thread.
    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let snapshot = setup
            saveQueue.async {
                let result = SetupStorage.save(snapshot)
                guard case .failure(let error) = result else { return }
                DispatchQueue.main.async { [weak self] in self?.notice = error.localizedDescription }
            }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }
}
