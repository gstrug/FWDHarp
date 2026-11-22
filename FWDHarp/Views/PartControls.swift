import SwiftUI

/// A part's instrument button and EDIT, with the sheets they open: the instrument
/// picker, the built-in sound list, and the plugin's own window full screen (in a
/// sheet it came up small; Graham, 2026-11-20). Used in the top bar for the plate and
/// on each mixer strip.
struct PartInstrumentButtons: View {
    @ObservedObject var store: InstrumentStore
    let part: HarpPart
    /// Narrow strips show the instrument chip above EDIT rather than beside it.
    var stacked = false
    /// Called before a choice is applied to a part with no sound of its own yet
    /// (auto-strum playing through the plate's), to give it one.
    var beforeChoosing: (() -> Void)? = nil

    @State private var showPicker = false
    @State private var showBuiltInSounds = false
    @State private var showPluginEditor = false

    var body: some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Button { showPicker = true } label: {
                HStack(spacing: 8) {
                    if let plugin = store.plugin(for: part) {
                        PluginIcon(plugin: plugin, size: 24)
                    } else {
                        Image(systemName: "pianokeys")
                    }
                    Text(store.instrumentName(for: part)).lineLimit(1)
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color(white: 0.87))
                .studioWindow()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(part.title) instrument: \(store.instrumentName(for: part))")
            .accessibilityHint("Choose another instrument")

            StudioTapButton(title: "EDIT") {
                if store.plugin(for: part) == nil { showBuiltInSounds = true } else { showPluginEditor = true }
            }
            .accessibilityLabel("Edit \(part.title) instrument")
        }
        .sheet(isPresented: $showPicker) {
            PluginPickerView(
                selectedPlugin: Binding(get: { store.plugin(for: part) }, set: { plugin in
                    giveOwnSoundIfNeeded()
                    store.choose(plugin, for: part)
                }),
                builtInSound: store.builtInSound(for: part)
            )
        }
        .sheet(isPresented: $showBuiltInSounds) {
            BuiltInSoundSheet(title: "\(part.title): Built-in Sound", current: store.builtInSound(for: part)) { sound in
                giveOwnSoundIfNeeded()
                store.setBuiltInSound(sound, for: part)
                // Play the new sound at once, so it can be heard.
                let id = InstrumentStore.trackID(for: part)
                store.engine.playNote(trackID: id, midiNote: 60, velocity: 100)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    store.engine.stopNote(trackID: id, midiNote: 60)
                }
            }
        }
        .fullScreenCover(isPresented: $showPluginEditor) {
            PluginEditorView(trackID: InstrumentStore.trackID(for: part),
                             trackName: "\(part.title): \(store.instrumentName(for: part))",
                             onCommitState: { store.captureInstrumentState(for: part) },
                             onReload: { store.reload(part) })
        }
    }
}

private extension PartInstrumentButtons {
    func giveOwnSoundIfNeeded() {
        if !store.hasOwnSound(part) { beforeChoosing?() }
    }
}

extension View {
    /// BLOCKING while an instrument loads: interrupting a fragile AUv3 while it
    /// instantiates crashes it (FWD lesson 1). Do not add .allowsHitTesting(false).
    func loadingOverlay(_ store: InstrumentStore) -> some View {
        modifier(LoadingOverlay(store: store))
    }

    /// The store's notices (a plugin that would not load, an effect left out) as alerts.
    func storeNotices(_ store: InstrumentStore) -> some View {
        modifier(StoreNotices(store: store))
    }
}

private struct LoadingOverlay: ViewModifier {
    @ObservedObject var store: InstrumentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if store.isLoading {
                    ZStack {
                        Color.black.opacity(0.55).ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView().controlSize(.large).tint(.white)
                            Text("Loading instruments…")
                                .font(.title3.bold()).foregroundStyle(.white)
                            if let name = store.loadingName {
                                Text(name).font(.callout).foregroundStyle(.white)
                            }
                            Text("Some plugins take a while. The screen unlocks when they're ready.")
                                .font(.footnote).foregroundStyle(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .padding(36)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .contentShape(Rectangle())
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.isLoading)
    }
}

private struct StoreNotices: ViewModifier {
    @ObservedObject var store: InstrumentStore

    func body(content: Content) -> some View {
        content.alert("FWD Harp", isPresented: Binding(
            get: { store.notice != nil },
            set: { if !$0 { store.notice = nil } }
        )) {
            Button("OK") { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }
}
