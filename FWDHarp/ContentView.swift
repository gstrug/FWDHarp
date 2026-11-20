import SwiftUI

/// The harp: chord pads under the left hand, the strum plate on the right, and the
/// instrument, key and effects along the top. The instrument, its sound, the effects
/// and the key are remembered between launches.
struct ContentView: View {
    @StateObject private var player = HarpPlayer()
    private var store: InstrumentStore { player.store }
    @State private var showPicker = false
    @State private var showBuiltInSounds = false
    @State private var showPluginEditor = false
    @State private var showCredits = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 24) {
                PadsView(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                StrumPlateView(player: player)
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
            }
            .padding(20)
        }
        .background(Color(white: 0.08).ignoresSafeArea())
        .sheet(isPresented: $showPicker) {
            PluginPickerView(
                selectedPlugin: Binding(get: { store.plugin }, set: { store.choose($0) }),
                builtInSound: store.builtInSound
            )
        }
        .sheet(isPresented: $showBuiltInSounds) {
            BuiltInSoundSheet(title: "Built-in Sound", current: store.builtInSound) { sound in
                store.setBuiltInSound(sound)
                // Play the new sound at once, so it can be heard.
                store.noteOn(60)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.noteOff(60) }
            }
        }
        // Full screen, as in FWD Sequencer: a plugin's own window needs the room, and in
        // a sheet it came up at a much smaller scale (Graham, 2026-11-20).
        .fullScreenCover(isPresented: $showPluginEditor) {
            PluginEditorView(trackID: InstrumentStore.partID,
                             trackName: store.instrumentName,
                             onCommitState: { store.captureInstrumentState() },
                             onReload: { store.reload() })
        }
        .sheet(isPresented: $showCredits) { CreditsView() }
        // BLOCKING while the instrument loads: interrupting a fragile AUv3 while it
        // instantiates crashes it (FWD lesson 1). Do not add .allowsHitTesting(false).
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
        // A safe moment to keep the instrument's sound and save (FWD lesson 3).
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                player.releaseAll()
                store.captureAndSave()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.isLoading)
        .alert("FWD Harp", isPresented: Binding(
            get: { store.notice != nil },
            set: { if !$0 { store.notice = nil } }
        )) {
            Button("OK") { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("FWD Harp")
                .font(.headline)
                .foregroundStyle(Color(white: 0.87))
            Spacer()
            keyMenu
            Button { showPicker = true } label: {
                HStack(spacing: 8) {
                    if let plugin = store.plugin {
                        PluginIcon(plugin: plugin, size: 24)
                    } else {
                        Image(systemName: "pianokeys")
                    }
                    Text(store.instrumentName).lineLimit(1)
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color(white: 0.87))
                .studioWindow()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Instrument: \(store.instrumentName)")
            .accessibilityHint("Choose another instrument")

            StudioTapButton(title: "EDIT") {
                if store.plugin == nil { showBuiltInSounds = true } else { showPluginEditor = true }
            }

            EffectsToggleButton(store: store)
                .accessibilityLabel("Edit Instrument")

            Button { showCredits = true } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(Color(white: 0.7))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About and Credits")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// The key the pads play in.
    private var keyMenu: some View {
        Menu {
            ForEach(MajorKey.all, id: \.tonic) { key in
                Button {
                    player.setKey(key)
                } label: {
                    if key == player.key { Label(key.name, systemImage: "checkmark") } else { Text(key.name) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("KEY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(StudioStyle.scaleText)
                Text(player.key.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioStyle.displayText)
            }
            .studioWindow()
        }
        .accessibilityLabel("Key: \(player.key.name) major")
    }
}

#Preview {
    ContentView()
}
