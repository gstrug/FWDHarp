import Foundation
import Combine
import os

/// The app side of MIDI control, copied from FWD Sequencer's MIDIControlCenter on
/// 2026-11-22 and cut down to the harp: which controllers are connected, which template
/// each one uses, MIDI Learn, turning incoming messages into changes, and following an
/// incoming MIDI clock. FWD's Write Notes and key routing to tracks are left out: a
/// controller's keys play the plate's instrument, as before, unless switched off.
///
/// One for the whole app, because links are app-wide. Incoming MIDI arrives on CoreMIDI's
/// thread; keys and clock are handled there, at once; links are queued and handled here
/// on the main thread, in batches.
@MainActor
final class MIDIControlCenter: ObservableObject {
    static let shared = MIDIControlCenter()

    // MARK: Published state

    /// Controllers and keyboards currently connected.
    @Published private(set) var sources: [MIDIInputManager.Source] = [] {
        didSet { learn.linksChanged(); refreshGate() }
    }
    /// Every template: the built-ins, then the user's own.
    @Published private(set) var templates: [MIDIControllerTemplate] = [] {
        didSet { learn.linksChanged(); refreshGate() }
    }
    /// Device name → template id. A device with no entry uses a built-in that suits it.
    @Published private(set) var assignments: [String: UUID] = [:] {
        didSet { learn.linksChanged(); refreshGate() }
    }
    /// Devices switched off in MIDI settings, by name.
    @Published private(set) var disabledDevices: Set<String> = [] {
        didSet { learn.linksChanged(); refreshGate() }
    }
    /// Devices whose keys do NOT play the plate's instrument, by name. Keys play it by
    /// default, as they always have.
    @Published private(set) var keysOffDevices: Set<String> = [] {
        didSet { refreshGate() }
    }
    /// When each device last sent something, for its activity light.
    @Published private(set) var lastActivity: [String: Date] = [:]

    /// MIDI clock in: follow its tempo and beat; from which device (nil: any); and
    /// whether its Start and Stop start and stop the drums. Remembered between launches.
    @Published private(set) var clock = MIDIClockSettings.load() {
        didSet { clock.save(); applyClock() }
    }

    /// Learn mode, in its own small object: every learnable control observes it, and it
    /// changes only when Learn is used, not on every MIDI message.
    let learn = MIDILearnState()

    /// What controls apply to: the harp on screen.
    private(set) weak var player: HarpPlayer?

    // MARK: Private

    private let input = MIDIInputManager.shared
    private let gate = MIDIInputGate()
    private var messageQueue: MIDIMessageQueue!
    private var pickup = MIDIPickup()
    private var learnObservers: Set<AnyCancellable> = []
    private var started = false

    private static let templatesKey = "FWDHarp.MIDIControllerTemplates.v1"
    private static let assignmentsKey = "FWDHarp.MIDIControllerAssignments.v1"
    private static let disabledKey = "FWDHarp.MIDIDisabledDevices.v1"
    private static let keysOffKey = "FWDHarp.MIDIKeysOffDevices.v1"

    private init() {
        loadSettings()
        messageQueue = MIDIMessageQueue { [weak self] batch in self?.handle(batch) }
        learn.$isOn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshGate() }
            .store(in: &learnObservers)
    }

    /// Start listening, for this harp. Called once the screen is up.
    func start(player: HarpPlayer) {
        self.player = player
        guard !started else { return }
        started = true
        input.onSourcesChanged = { [weak self] list in
            Task { @MainActor in self?.sources = list }
        }
        let queue: MIDIMessageQueue = messageQueue
        let gate = gate
        let conductor = player.conductor
        player.store.startMIDIInput(gate: gate) { source, message in
            queue.push(source, message)
        }
        // Clock and transport, on CoreMIDI's thread straight to the conductor, so the
        // beat is as close to the other app's as it can be.
        input.onRealtime = { source, status, time in
            guard gate.followsClock(from: source.name) else { return }
            switch status {
            case 0xF8: conductor.clockPulse(at: time)
            case 0xFA, 0xFB: conductor.clockStart()
            case 0xFC: conductor.clockStop()
            default: break
            }
        }
        input.start()
        sources = input.sources
        applyClock()
        refreshGate()
    }

    // MARK: Clock

    func setClock(_ settings: MIDIClockSettings) {
        clock = settings
    }

    private func applyClock() {
        player?.setFollowsClock(clock.follow, transport: clock.transport)
        refreshGate()
    }

    // MARK: Templates and devices

    /// Stored as a device's assignment when the user picked "None".
    static let noTemplate = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// The template a device uses: the one assigned to it, else a built-in that suits it.
    func template(forDevice name: String) -> MIDIControllerTemplate? {
        if let id = assignments[name] {
            if id == Self.noTemplate { return nil }
            if let t = templates.first(where: { $0.id == id }) { return t }
        }
        return templates.first { $0.isBuiltIn && $0.suits(deviceNamed: name) }
    }

    /// `nil` means "None": the device sends nothing to the app.
    func assign(_ templateID: UUID?, toDevice name: String) {
        assignments[name] = templateID ?? Self.noTemplate
        pickup.reset()
        saveSettings()
    }

    func setDevice(_ name: String, enabled: Bool) {
        if enabled { disabledDevices.remove(name) } else { disabledDevices.insert(name) }
        saveSettings()
    }

    func isEnabled(_ name: String) -> Bool { !disabledDevices.contains(name) }

    func keysPlayPlate(_ name: String) -> Bool { !keysOffDevices.contains(name) }

    func setKeysPlayPlate(_ on: Bool, forDevice name: String) {
        if on { keysOffDevices.remove(name) } else { keysOffDevices.insert(name) }
        saveSettings()
    }

    /// A copy of a template under a new name.
    @discardableResult
    func duplicate(_ templateID: UUID, named name: String? = nil) -> MIDIControllerTemplate? {
        guard let source = templates.first(where: { $0.id == templateID }) else { return nil }
        let copy = MIDIControllerTemplate(
            name: uniqueName(name ?? source.name.replacingOccurrences(of: " (factory)", with: "") + " copy"),
            mappings: source.mappings.map { MIDIControlMapping(source: $0.source, target: $0.target, pickup: $0.pickup) },
            isBuiltIn: false, deviceNameHint: source.deviceNameHint)
        templates.append(copy)
        saveSettings()
        return copy
    }

    @discardableResult
    func newTemplate(named name: String, deviceNameHint: String? = nil) -> MIDIControllerTemplate {
        let fresh = MIDIControllerTemplate(name: uniqueName(name), deviceNameHint: deviceNameHint)
        templates.append(fresh)
        saveSettings()
        return fresh
    }

    func rename(_ templateID: UUID, to name: String) {
        guard let i = templates.firstIndex(where: { $0.id == templateID }), !templates[i].isBuiltIn else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        templates[i].name = uniqueName(trimmed, excluding: templateID)
        saveSettings()
    }

    func delete(_ templateID: UUID) {
        guard let i = templates.firstIndex(where: { $0.id == templateID }), !templates[i].isBuiltIn else { return }
        templates.remove(at: i)
        for (device, id) in assignments where id == templateID { assignments.removeValue(forKey: device) }
        saveSettings()
    }

    /// Whether a target is linked on any connected controller, and to what — for the
    /// label Learn mode shows on each control.
    func linkDescription(for target: MIDIControlTarget) -> String? {
        for source in sources where isEnabled(source.name) {
            if let mapping = template(forDevice: source.name)?.mapping(for: target) {
                return mapping.source.displayName
            }
        }
        return nil
    }

    /// Remove a control's link from every connected controller's template.
    func forget(_ target: MIDIControlTarget) {
        for source in sources {
            guard let id = editableTemplateID(forDevice: source.name, creating: false),
                  let i = templates.firstIndex(where: { $0.id == id }) else { continue }
            templates[i].forget(target)
        }
        saveSettings()
    }

    func removeLink(_ target: MIDIControlTarget, fromTemplate templateID: UUID) {
        guard let i = templates.firstIndex(where: { $0.id == templateID }), !templates[i].isBuiltIn else { return }
        templates[i].forget(target)
        pickup.reset()
        saveSettings()
    }

    /// Tell the MIDI thread what it needs: which notes and controllers are linked (they
    /// control the app, so they do not play the plate), Learn, switched-off devices,
    /// keys switched off, and the clock's source.
    private func refreshGate() {
        var linkedNotes: [String: Set<MIDIControlSource>] = [:]
        var linkedControls: [String: Set<MIDIControlSource>] = [:]
        for source in sources where isEnabled(source.name) {
            guard let t = template(forDevice: source.name) else { continue }
            linkedNotes[source.name] = Set(t.mappings.map(\.source).filter { $0.kind == .note })
            linkedControls[source.name] = Set(t.mappings.map(\.source).filter { $0.kind == .controlChange })
        }
        gate.update(MIDIInputGate.Config(linkedNotes: linkedNotes, linkedControls: linkedControls,
                                         disabledDevices: disabledDevices, keysOffDevices: keysOffDevices,
                                         learning: learn.isOn, followClock: clock.follow,
                                         clockSource: clock.source))
    }

    // MARK: Receiving

    /// A batch of messages, in arrival order, on the main thread.
    private func handle(_ batch: [(MIDIInputManager.Source, MIDIControlMessage)]) {
        guard !batch.isEmpty else { return }

        // The activity lights need a new time only every tenth of a second: setting it
        // for every batch redrew whatever watches this object for every key played.
        let now = Date()
        for name in Set(batch.map { $0.0.name })
        where lastActivity[name].map({ now.timeIntervalSince($0) > 0.1 }) ?? true {
            lastActivity[name] = now
        }

        // A continuous control only needs its LAST position in a batch; buttons are
        // handled in order, every press and release, so none is lost.
        var lastContinuous: [String: Int] = [:]
        for (i, (source, message)) in batch.enumerated() where message.kind == .controlChange {
            lastContinuous["\(source.name)|\(message.channel)|\(message.number)"] = i
        }

        for (i, (source, message)) in batch.enumerated() {
            guard isEnabled(source.name) else { continue }
            if learn.isOn, let target = learn.target {
                makeLink(target, from: source, message)
                continue
            }
            let mappings = template(forDevice: source.name)?.mappings(matching: message) ?? []
            for mapping in mappings {
                if mapping.target.isContinuous {
                    let key = "\(source.name)|\(message.channel)|\(message.number)"
                    guard lastContinuous[key] == i || message.kind == .note else { continue }
                    applyContinuous(mapping, message.fraction)
                } else {
                    applyButton(mapping.target, pressed: message.isPress)
                }
            }
        }
    }

    // MARK: Learn

    private func makeLink(_ target: MIDIControlTarget, from source: MIDIInputManager.Source,
                          _ message: MIDIControlMessage) {
        // Ignore the release half of a button press, so the link is made from the
        // message that was meant.
        if message.kind == .note && !message.isPress { return }
        guard let id = editableTemplateID(forDevice: source.name, creating: true),
              let i = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[i].learn(MIDIControlSource(message), for: target)
        saveSettings()
        learn.target = nil
        pickup.reset()
    }

    /// The template Learn should write to for a device. Built-ins are never edited: the
    /// first link learned on one makes the device its own copy. A device with no
    /// template gets one named after it.
    private func editableTemplateID(forDevice name: String, creating: Bool) -> UUID? {
        if let current = template(forDevice: name) {
            if !current.isBuiltIn { return current.id }
            guard creating, let copy = duplicate(current.id, named: name) else { return nil }
            assign(copy.id, toDevice: name)
            return copy.id
        }
        guard creating else { return nil }
        let fresh = MIDIControllerTemplate(name: uniqueName(name), deviceNameHint: name)
        templates.append(fresh)
        assign(fresh.id, toDevice: name)
        return fresh.id
    }

    // MARK: Applying to the harp

    /// The harp, unless instruments are loading: touches are blocked then on purpose (a
    /// fragile plugin can crash if interrupted), and a controller is held off too.
    private var activePlayer: HarpPlayer? {
        guard let player, !player.store.isLoading else { return nil }
        return player
    }

    private func applyContinuous(_ mapping: MIDIControlMapping, _ fraction: Double) {
        guard let player = activePlayer else { return }
        let store = player.store
        switch mapping.target {
        case .masterVolume:
            let current = MIDIControlScaling.fraction(forGain: store.setup.masterVolume)
            guard pickup.shouldApply(mapping, incoming: fraction, current: current) else { return }
            store.setMasterVolume(MIDIControlScaling.gain(forFraction: fraction))
        case .tempo:
            // An incoming clock sets the tempo while it is followed.
            guard !player.isFollowingClock else { return }
            let current = MIDIControlScaling.fraction(forTempo: player.tempo)
            guard pickup.shouldApply(mapping, incoming: fraction, current: current) else { return }
            player.setTempo(MIDIControlScaling.tempo(forFraction: fraction))
        case .partVolume(let part):
            let current = MIDIControlScaling.fraction(forGain: store.setup.mix(of: part).volume)
            guard pickup.shouldApply(mapping, incoming: fraction, current: current) else { return }
            store.setVolume(MIDIControlScaling.gain(forFraction: fraction), for: part)
        case .partPan(let part):
            let current = MIDIControlScaling.fraction(forPan: store.setup.mix(of: part).pan)
            guard pickup.shouldApply(mapping, incoming: fraction, current: current) else { return }
            store.setPan(MIDIControlScaling.pan(forFraction: fraction), for: part)
        default:
            // A button target reached through a knob: treat crossing half way as a press.
            applyButton(mapping.target, pressed: fraction >= 0.5)
        }
    }

    /// Buttons act on the press; pads hear the release too, so a held button holds
    /// the chord as a finger does.
    private func applyButton(_ target: MIDIControlTarget, pressed: Bool) {
        guard let player = activePlayer else { return }
        if target.hearsRelease, case .pad(let pad) = target {
            if pressed { player.press(pad) } else { player.release(pad) }
            return
        }
        guard pressed else { return }
        let store = player.store
        switch target {
        case .hold:             player.setHolding(!player.selection.isHolding)
        case .autoStrum:        player.setAutoStrumming(!player.isAutoStrumming)
        case .tapTempo:         if !player.isFollowingClock { player.tapTempo() }
        case .panic:            player.panic()
        case .octaveUp:         player.shiftOctave(by: 1)
        case .autoOctaveUp:     player.shiftAutoOctave(by: 1)
        case .autoOctaveDown:   player.shiftAutoOctave(by: -1)
        case .octaveDown:       player.shiftOctave(by: -1)
        case .rhythmStartStop:  player.toggleRhythm()
        case .rhythmStop:       if player.rhythm.running { player.toggleRhythm() }
        case .rhythmSync:       player.armRhythm(!player.isRhythmArmed)
        case .fill:             player.fill()
        case .introOutro:
            if player.rhythm.running {
                if !player.rhythm.intro { player.outro() }
            } else {
                player.setRhythmIntro(!player.rhythmIntro)
            }
        case .variationA:       player.setRhythmVariation(.a)
        case .variationB:       player.setRhythmVariation(.b)
        case .previousStyle:    player.stepRhythmStyle(by: -1)
        case .nextStyle:        player.stepRhythmStyle(by: 1)
        case .partSolo(let part):
            store.setSoloed(!store.isSoloed(part), for: part)
        case .partMute(let part):
            store.setMuted(!store.setup.mix(of: part).muted, for: part)
        case .partEffects(let part):
            store.setEffectsChainBypassed(!store.effectsBypassed(for: part), for: part)
        case .pad, .tempo, .masterVolume, .partVolume, .partPan:
            break   // handled above
        }
    }

    // MARK: Persistence

    private func uniqueName(_ base: String, excluding id: UUID? = nil) -> String {
        let taken = Set(templates.filter { $0.id != id }.map(\.name))
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        var user: [MIDIControllerTemplate] = []
        if let data = defaults.data(forKey: Self.templatesKey),
           let decoded = try? JSONDecoder().decode([MIDIControllerTemplate].self, from: data) {
            user = decoded.filter { !$0.isBuiltIn }
        }
        templates = MIDIBuiltInTemplates.all + user
        if let data = defaults.data(forKey: Self.assignmentsKey),
           let decoded = try? JSONDecoder().decode([String: UUID].self, from: data) {
            assignments = decoded
        }
        disabledDevices = Set(defaults.stringArray(forKey: Self.disabledKey) ?? [])
        keysOffDevices = Set(defaults.stringArray(forKey: Self.keysOffKey) ?? [])
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        // Built-ins come from the code, so only the user's own are stored.
        if let data = try? JSONEncoder().encode(templates.filter { !$0.isBuiltIn }) {
            defaults.set(data, forKey: Self.templatesKey)
        }
        if let data = try? JSONEncoder().encode(assignments) {
            defaults.set(data, forKey: Self.assignmentsKey)
        }
        defaults.set(Array(disabledDevices).sorted(), forKey: Self.disabledKey)
        defaults.set(Array(keysOffDevices).sorted(), forKey: Self.keysOffKey)
    }
}

/// MIDI clock in, as chosen in MIDI settings. App-wide, like FWD's clock out setting.
nonisolated struct MIDIClockSettings: Codable, Equatable {
    /// Follow an incoming MIDI clock's tempo and beat.
    var follow = false
    /// The device to follow, by name; nil: whichever sends a clock.
    var source: String? = nil
    /// The clock's Start and Stop start and stop the drums.
    var transport = true

    private static let key = "FWDHarp.MIDIClockIn.v1"

    static func load() -> MIDIClockSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(MIDIClockSettings.self, from: data) else {
            return MIDIClockSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// What CoreMIDI's thread needs to know, behind a lock: whether a key plays the plate
/// or belongs to a link, and whether a clock is followed.
nonisolated final class MIDIInputGate: @unchecked Sendable {
    struct Config {
        var linkedNotes: [String: Set<MIDIControlSource>] = [:]
        var linkedControls: [String: Set<MIDIControlSource>] = [:]
        var disabledDevices: Set<String> = []
        var keysOffDevices: Set<String> = []
        var learning = false
        var followClock = false
        var clockSource: String? = nil
    }

    private let lock = OSAllocatedUnfairLock()
    private var config = Config()

    func update(_ new: Config) {
        lock.lock(); config = new; lock.unlock()
    }

    /// Whether this message plays the plate's instrument: a key or controller from a
    /// device in use, whose keys play the plate, that no link uses, while Learn is off.
    /// A key let go always gets through, so nothing is left hanging.
    func playsPlate(device: String, _ message: MIDIControlMessage) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if config.disabledDevices.contains(device) || config.keysOffDevices.contains(device) { return false }
        let source = MIDIControlSource(message)
        switch message.kind {
        case .note:
            if config.linkedNotes[device]?.contains(source) == true { return false }
            return !config.learning || !message.isPress
        case .controlChange:
            // Channel-mode controllers (120 and up) are the app's to send.
            if message.number >= 120 || config.learning { return false }
            return config.linkedControls[device]?.contains(source) != true
        }
    }

    func playsPerformance(device: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !config.disabledDevices.contains(device) && !config.keysOffDevices.contains(device)
            && !config.learning
    }

    func followsClock(from device: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard config.followClock, !config.disabledDevices.contains(device) else { return false }
        return config.clockSource == nil || config.clockSource == device
    }
}

/// Collects messages on CoreMIDI's thread and hands them to the main thread in batches.
nonisolated final class MIDIMessageQueue: @unchecked Sendable {
    typealias Item = (MIDIInputManager.Source, MIDIControlMessage)
    private let lock = OSAllocatedUnfairLock()
    private var items: [Item] = []
    private var scheduled = false
    private let deliver: ([Item]) -> Void

    /// `deliver` runs on the main thread.
    init(deliver: @escaping ([Item]) -> Void) { self.deliver = deliver }

    func push(_ source: MIDIInputManager.Source, _ message: MIDIControlMessage) {
        lock.lock()
        items.append((source, message))
        let start = !scheduled
        scheduled = true
        lock.unlock()
        guard start else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            lock.lock()
            let batch = items
            items.removeAll(keepingCapacity: true)
            scheduled = false
            lock.unlock()
            deliver(batch)
        }
    }
}

/// MIDI Learn's on-screen state. See MIDIControlCenter.learn.
@MainActor
final class MIDILearnState: ObservableObject {
    /// Learnable controls are outlined and a tap selects one instead of using it.
    @Published var isOn = false {
        didSet {
            if !isOn { target = nil }
            // One mode that takes over taps at a time, as in FWD.
            if isOn { HelpCenter.shared.isOn = false }
        }
    }
    /// The control waiting to be linked to the next message that arrives.
    @Published var target: MIDIControlTarget?
    /// Bumped whenever links, templates or devices change, so the link labels refresh.
    @Published private(set) var revision = 0

    func linksChanged() { revision &+= 1 }
}
