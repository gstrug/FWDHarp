import Foundation
import Combine

/// FWD Harp's sound: one instrument (the built-in General MIDI sound or a hosted AUv3)
/// and its effects, with FWD Sequencer's load protection (generation-tokened loads, a
/// 30 s time limit with the built-in sound as fallback, a blocking overlay while
/// loading) and its saving (SetupStorage: backups and quarantine).
///
/// Plugin state is captured only at safe moments — an editor closing, the app going to
/// the background — and only for an instrument whose sound may have changed (FWD
/// lesson 3), so a plugin that ignored its restore never has its default saved over the
/// user's patch.
final class InstrumentStore: ObservableObject {
    /// The engine keys everything by a track id, as in FWD. FWD Harp has one part, so
    /// one fixed id.
    static let partID = UUID(uuidString: "6E0A7C8E-3B1F-4D5A-9C2E-0000000000A1")!

    @Published private(set) var setup = HarpSetup() {
        didSet { if setup != oldValue { scheduleSave() } }
    }
    /// True while the instrument loads; the screen is blocked until it is ready
    /// (FWD lesson 1: interrupting a fragile AUv3 while it loads crashes it).
    @Published private(set) var isLoading = false
    @Published private(set) var loadingName: String?
    @Published var notice: String?

    let engine = AudioEngineManager.shared
    private var loads = PluginLoadTracker()
    private var saveWorkItem: DispatchWorkItem?
    /// Writes happen here, off the main thread, from a copy of the setup: saving never
    /// touches the live document (FWD lesson 4).
    private let saveQueue = DispatchQueue(label: "com.fwdharp.setup-save", qos: .utility)

    var plugin: PluginInfo? { setup.instrument }
    var builtInSound: Int { setup.builtInSound }
    var effects: [PluginSlot] { setup.effects }

    var instrumentName: String {
        plugin?.name ?? GeneralMIDI.soundName(builtInSound)
    }

    init() {
        let loaded = SetupStorage.load()
        switch loaded {
        case .loaded(let saved), .restoredFromBackup(let saved): setup = saved
        case .fresh, .unreadable: break
        }
        notice = loaded.notice
        // Not a change: assigning the loaded setup must not write it straight back.
        saveWorkItem?.cancel()
        saveWorkItem = nil

        engine.onStatusChange = { [weak self] status in
            if case .failed(let message) = status { self?.notice = message }
        }
        engine.onEffectRefused = { [weak self] name in
            self?.notice = "\(name) could not be connected, so it has been left out and the instrument plays without it. It may need audio this app can't give it; try another effect, or remove it."
        }
        engine.onPlaybackInterrupted = { [weak self] _ in
            self?.engine.allNotesOff()
        }
        // The audio system restarted and every node was thrown away: build the part
        // again, with its saved sound.
        engine.onRecoveryRequired = { [weak self] in
            self?.buildPart()
        }
        buildPart()
        startMIDIInput()
    }

    /// Put the instrument and its effects into the engine from the setup.
    private func buildPart() {
        loads.cancelAll()
        isLoading = false
        engine.addTrack(id: Self.partID, builtInSound: setup.builtInSound)
        if let plugin = setup.instrument {
            load(plugin, state: setup.instrumentState)
        }
        loadEffects()
    }

    // MARK: - Instrument

    /// Choose the instrument: a plugin, or nil for the built-in sound. Choosing the one
    /// already playing loads it again, which is how a plugin that timed out is retried.
    func choose(_ newPlugin: PluginInfo?) {
        guard newPlugin != nil || plugin != nil else { return }
        if newPlugin == plugin, let newPlugin {
            // Same plugin again: reload with its saved patch, not a blank one.
            load(newPlugin, state: setup.instrumentState)
            return
        }
        setup.instrument = newPlugin
        setup.instrumentState = nil   // a fresh plugin starts on its own default sound
        load(newPlugin, state: nil)
    }

    /// Load the current instrument again, for a plugin whose window came up blank.
    func reload() {
        load(plugin, state: setup.instrumentState)
    }

    func setBuiltInSound(_ sound: Int) {
        setup.builtInSound = sound
        engine.setBuiltInSound(sound, for: Self.partID)
    }

    /// The instrument's editor closed: keep its sound.
    func captureInstrumentState() {
        guard !isLoading, plugin != nil else { return }
        if let state = engine.captureState(for: Self.partID), state != setup.instrumentState {
            setup.instrumentState = state
        }
    }

    private func load(_ info: PluginInfo?, state: Data?) {
        let token = loads.begin(for: Self.partID)
        loadingName = info?.name ?? "Built-in sound"
        isLoading = true
        engine.loadPlugin(info, for: Self.partID, stateData: state) { [weak self] result in
            guard let self else { return }
            guard loads.finish(for: Self.partID, token: token) else { return }
            isLoading = false
            loadingName = nil
            switch result {
            case .success, .failure(.cancelled):
                break
            case .failure(let error):
                notice = error.localizedDescription
            }
        }
    }

    // MARK: - Notes

    func noteOn(_ note: UInt8, velocity: UInt8 = 100) {
        engine.playNote(trackID: Self.partID, midiNote: note, velocity: velocity)
    }

    func noteOff(_ note: UInt8) {
        engine.stopNote(trackID: Self.partID, midiNote: note)
    }

    /// A MIDI keyboard plays the instrument directly: its notes, sustain pedal, mod
    /// wheel, pitch bend and aftertouch. Runs on CoreMIDI's thread and goes straight to
    /// the engine, which is thread-safe and drops MIDI while a plugin loads. Chord pads
    /// and MIDI Learn for the app's own controls come later.
    private func startMIDIInput() {
        let engine = engine
        let part = Self.partID
        let input = MIDIInputManager.shared
        input.onMessage = { @Sendable _, message in
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
        input.onPerformanceMessage = { @Sendable _, status, data1, data2 in
            engine.sendPerformanceMessage(trackID: part, status: status, data1: data1, data2: data2)
        }
        input.start()
    }

    // MARK: - Effects (as FWD Sequencer's SongStore)

    private func loadEffects() {
        for (index, slot) in setup.effects.enumerated() {
            // Bypass goes in with the load: loading is asynchronous, so setting it
            // afterwards would set it on a chain the effect has not joined yet.
            engine.loadEffect(slot.pluginInfo, at: index, for: Self.partID,
                              stateData: slot.stateData,
                              bypassed: setup.effectIsSilenced(at: index)) { [weak self] result in
                guard case .failure(let error) = result else { return }
                self?.notice = error.localizedDescription
            }
        }
    }

    func addEffect(_ info: PluginInfo) {
        guard setup.effects.count < HarpSetup.maximumEffects else {
            notice = "Up to \(HarpSetup.maximumEffects) effects can be added."
            return
        }
        let position = setup.effects.count
        setup.effects.append(PluginSlot(pluginInfo: info))
        // Joins switched out if the chain is switched out.
        engine.loadEffect(info, at: position, for: Self.partID,
                          bypassed: setup.effectsBypassed) { [weak self] result in
            guard case .failure(let error) = result else { return }
            self?.notice = error.localizedDescription
        }
    }

    /// Order is signal order. The identical move is applied to the setup and to the
    /// units, which keeps them in step.
    func moveEffects(from source: IndexSet, to destination: Int) {
        guard !setup.effects.isEmpty else { return }
        var slots = setup.effects
        let moving = source.sorted().compactMap { slots.indices.contains($0) ? slots[$0] : nil }
        slots = slots.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        slots.insert(contentsOf: moving, at: min(max(0, insertAt), slots.count))
        setup.effects = slots
        engine.moveEffect(from: source, to: destination, for: Self.partID)
    }

    /// Swap one effect for another in the same place. The new one starts fresh and in
    /// circuit, since you are swapping it in to hear it.
    func replaceEffect(at index: Int, with info: PluginInfo) {
        guard setup.effects.indices.contains(index),
              setup.effects[index].pluginInfo != info else { return }
        setup.effects[index] = PluginSlot(pluginInfo: info)
        engine.removeEffect(at: index, for: Self.partID)
        engine.loadEffect(info, at: index, for: Self.partID,
                          bypassed: setup.effectsBypassed) { [weak self] result in
            guard case .failure(let error) = result else { return }
            self?.notice = error.localizedDescription
        }
    }

    func removeEffect(at index: Int) {
        guard setup.effects.indices.contains(index) else { return }
        setup.effects.remove(at: index)
        engine.removeEffect(at: index, for: Self.partID)
    }

    func setEffectBypassed(_ bypassed: Bool, at index: Int) {
        guard setup.effects.indices.contains(index) else { return }
        setup.effects[index].isBypassed = bypassed ? true : nil
        // While the chain is switched out the effect stays silent; its own setting is
        // still kept, and takes effect when the chain comes back in.
        engine.setEffectBypassed(setup.effectIsSilenced(at: index), at: index, for: Self.partID)
    }

    func setEffectsChainBypassed(_ bypassed: Bool) {
        setup.effectsBypassed = bypassed
        for index in setup.effects.indices {
            engine.setEffectBypassed(setup.effectIsSilenced(at: index), at: index, for: Self.partID)
        }
    }

    /// An effect's editor closed: keep its settings.
    func captureEffectState(at index: Int) {
        guard setup.effects.indices.contains(index),
              let state = engine.captureEffectState(at: index, for: Self.partID) else { return }
        setup.effects[index].stateData = state
    }

    // MARK: - Saving

    /// A safe moment (the app going to the background): capture the instrument if its
    /// sound may have changed, then save at once.
    func captureAndSave() {
        if engine.mayHaveNewState(Self.partID) { captureInstrumentState() }
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
