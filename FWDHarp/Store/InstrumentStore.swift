import Foundation
import Combine

/// The one instrument FWD Harp plays: the built-in General MIDI sound or a hosted AUv3,
/// with FWD Sequencer's load protection (generation-tokened loads, a 30 s time limit
/// with the built-in sound as fallback, and a blocking overlay while loading).
///
/// First version, for testing the hosting on the iPad: the choice is not saved yet,
/// so the app starts on the built-in harp sound each time. Saving (with FWD's backups)
/// and effects come next.
final class InstrumentStore: ObservableObject {
    /// The engine keys everything by a track id, as in FWD. FWD Harp has one part, so
    /// one fixed id.
    static let partID = UUID(uuidString: "6E0A7C8E-3B1F-4D5A-9C2E-0000000000A1")!

    /// General MIDI program 46, Orchestral Harp: a harp app should sound like one.
    static let defaultBuiltInSound = 46

    @Published private(set) var plugin: PluginInfo?
    @Published private(set) var builtInSound = InstrumentStore.defaultBuiltInSound
    /// True while an instrument loads; the screen is blocked until it is ready
    /// (FWD lesson 1: interrupting a fragile AUv3 while it loads crashes it).
    @Published private(set) var isLoading = false
    @Published private(set) var loadingName: String?
    @Published var notice: String?

    let engine = AudioEngineManager.shared
    private var loads = PluginLoadTracker()

    init() {
        engine.addTrack(id: Self.partID, builtInSound: builtInSound)
        engine.onStatusChange = { [weak self] status in
            if case .failed(let message) = status { self?.notice = message }
        }
        engine.onEffectRefused = { [weak self] name in
            self?.notice = "\(name) could not be connected, so it has been left out and the instrument plays without it."
        }
        engine.onPlaybackInterrupted = { [weak self] _ in
            self?.engine.allNotesOff()
        }
        // The audio system restarted and every node was thrown away: build the part
        // again and reload its instrument.
        engine.onRecoveryRequired = { [weak self] in
            guard let self else { return }
            engine.addTrack(id: Self.partID, builtInSound: builtInSound)
            if plugin != nil { load(plugin) }
        }
    }

    /// Choose the instrument: a plugin, or nil for the built-in sound. Choosing the one
    /// already playing loads it again, which is how a plugin that timed out is retried.
    func choose(_ newPlugin: PluginInfo?) {
        guard newPlugin != nil || plugin != nil else { return }
        plugin = newPlugin
        load(newPlugin)
    }

    /// Load the current instrument again, for a plugin whose window came up blank.
    func reload() {
        load(plugin)
    }

    func setBuiltInSound(_ sound: Int) {
        builtInSound = sound
        engine.setBuiltInSound(sound, for: Self.partID)
    }

    var instrumentName: String {
        plugin?.name ?? GeneralMIDI.soundName(builtInSound)
    }

    func noteOn(_ note: UInt8, velocity: UInt8 = 100) {
        engine.playNote(trackID: Self.partID, midiNote: note, velocity: velocity)
    }

    func noteOff(_ note: UInt8) {
        engine.stopNote(trackID: Self.partID, midiNote: note)
    }

    private func load(_ info: PluginInfo?) {
        let token = loads.begin(for: Self.partID)
        loadingName = info?.name ?? "Built-in sound"
        isLoading = true
        engine.loadPlugin(info, for: Self.partID) { [weak self] result in
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
}
