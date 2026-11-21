import SwiftUI
import UIKit

/// A part's AUv3 effect chain: instrument → effects, in signal order, → its channel.
/// Copied from FWD Sequencer's TrackEffectsView on 2026-11-20.
struct EffectsView: View {
    @ObservedObject var store: InstrumentStore
    let part: HarpPart
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var editingIndex: Int?
    /// The slot whose effect is being swapped for another, if any.
    @State private var replacingIndex: Int?

    private var slots: [PluginSlot] { store.effects(for: part) }

    var body: some View {
        NavigationStack {
            List {
                // The same switch as tapping the FX button, so its state is visible and
                // changeable here too. Each effect's own Bypass is separate.
                if !slots.isEmpty {
                    Section {
                        Toggle("Effects On", isOn: Binding(
                            get: { !store.effectsBypassed(for: part) },
                            set: { store.setEffectsChainBypassed(!$0, for: part) }
                        ))
                        .tint(.green)
                    } footer: {
                        Text("Switches the whole chain in or out. Effects bypassed "
                             + "individually stay bypassed when it comes back on.")
                    }
                }

                Section {
                    if slots.isEmpty {
                        Text("No effects").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                            row(index: index, slot: slot)
                                // Removing is the row's own Remove button; without this,
                                // the always-on edit mode below would add a red delete
                                // control as well.
                                .deleteDisabled(true)
                        }
                        .onMove { source, destination in
                            store.moveEffects(from: source, to: destination, for: part)
                        }
                    }
                } header: {
                    Text("Chain")
                } footer: {
                    Text("Effects process the \(part.title.lowercased()) part's instrument, top to bottom. Their own settings "
                         + "are saved."
                         + (slots.count > 1 ? " Drag the handles to reorder them." : ""))
                }

                Section {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Add Effect", systemImage: "plus")
                    }
                    .disabled(slots.count >= HarpSetup.maximumEffects)
                } footer: {
                    if slots.count >= HarpSetup.maximumEffects {
                        Text("Up to \(HarpSetup.maximumEffects) effects.")
                    }
                }
            }
            // Reordering is always on once there is an order to change, so the drag
            // handles are simply there (in FWD an Edit button hid them, and nobody
            // thought to press it).
            .environment(\.editMode, .constant(slots.count > 1 ? .active : .inactive))
            .navigationTitle("\(part.title) Effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPicker) {
                EffectPickerView { info in
                    store.addEffect(info, to: part)
                    showPicker = false
                }
            }
            .sheet(item: Binding(
                get: { replacingIndex.map { EffectEditorTarget(index: $0) } },
                set: { replacingIndex = $0?.index }
            )) { target in
                EffectPickerView { info in
                    store.replaceEffect(at: target.index, with: info, for: part)
                    replacingIndex = nil
                }
            }
            // Full screen, like the instrument's window: a plugin's own window needs
            // the room.
            .fullScreenCover(item: Binding(
                get: { editingIndex.map { EffectEditorTarget(index: $0) } },
                set: { editingIndex = $0?.index }
            )) { target in
                PluginEditorView(
                    trackID: InstrumentStore.trackID(for: part),
                    trackName: slots[safe: target.index]?.pluginInfo.name ?? "Effect",
                    effectIndex: target.index,
                    // Capture on close, exactly as the instrument's editor does, so a
                    // tweak survives without thinking to save anything.
                    onCommitState: { store.captureEffectState(at: target.index, for: part) }
                )
            }
        }
    }

    @ViewBuilder
    private func row(index: Int, slot: PluginSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                PluginIcon(plugin: slot.pluginInfo, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.pluginInfo.name).font(.body).lineLimit(1)
                    Text(slot.pluginInfo.manufacturerName).font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button { editingIndex = index } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered).controlSize(.small)

                Toggle("Bypass", isOn: Binding(
                    get: { slot.bypassed },
                    set: { store.setEffectBypassed($0, at: index, for: part) }
                ))
                .toggleStyle(.button).controlSize(.small).tint(.orange)

                Spacer(minLength: 0)

                // Swap for a different effect in the same place in the chain, rather
                // than removing it, adding the new one and dragging it back into line.
                Button { replacingIndex = index } label: {
                    Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered).controlSize(.small)

                Button(role: .destructive) {
                    store.removeEffect(at: index, from: part)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The FX button: green when at least one effect is processing, orange when the chain
/// is switched out or every effect is bypassed, grey with none. Tap switches the whole
/// chain in and out; long press opens the list. With no effects, a tap opens the list.
///
/// Drawn rather than a Button: a Button fires its action at the end of a long press as
/// well, so the chain would toggle every time the list was opened.
struct EffectsToggleButton: View {
    @ObservedObject var store: InstrumentStore
    let part: HarpPart
    @State private var showEffects = false

    private var slots: [PluginSlot] { store.effects(for: part) }

    private enum Status { case none, active, allBypassed }
    private var status: Status {
        if slots.isEmpty { return .none }
        if store.effectsBypassed(for: part) || slots.allSatisfy(\.bypassed) { return .allBypassed }
        return .active
    }

    private var tint: Color {
        switch status {
        case .none: return .secondary
        case .active: return .green
        case .allBypassed: return .orange
        }
    }

    private var accessibilityValue: String {
        switch status {
        case .none: return "No effects"
        case .active: return "\(slots.count) loaded, \(slots.filter { !$0.bypassed }.count) active"
        case .allBypassed:
            return store.effectsBypassed(for: part) ? "\(slots.count) loaded, switched off"
                                               : "\(slots.count) loaded, all bypassed"
        }
    }

    var body: some View {
        StudioChipLabel(title: slots.isEmpty ? "FX" : "FX \(slots.count)", tint: tint,
                        look: status == .none ? .off : .status)
            .onTapGesture { tap() }
            .onLongPressGesture(minimumDuration: 0.45) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showEffects = true
            }
            .sheet(isPresented: $showEffects) { EffectsView(store: store, part: part) }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(part.title) effects")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(slots.isEmpty ? "Opens the effects list"
                               : "Switches all effects on or off. Use the Edit Effects action to change them.")
            .accessibilityAction { tap() }
            .accessibilityAction(named: Text("Edit Effects")) { showEffects = true }
    }

    private func tap() {
        if slots.isEmpty { showEffects = true }
        else { store.setEffectsChainBypassed(!store.effectsBypassed(for: part), for: part) }
    }
}

/// Identifiable wrapper so a plain index can drive `.sheet(item:)`.
private struct EffectEditorTarget: Identifiable {
    let index: Int
    var id: Int { index }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Effect chooser. Separate from the instrument picker because it lists a different
/// scan (`aufx`/`aumf`) and has no "no plugin" option — removing is how you clear a slot.
struct EffectPickerView: View {
    @ObservedObject private var manager = PluginManager.shared
    @Environment(\.dismiss) private var dismiss
    let onSelect: (PluginInfo) -> Void

    var body: some View {
        NavigationStack {
            List {
                if manager.effects.isEmpty {
                    Text(manager.isScanning ? "Scanning…" : "No AUv3 effects installed")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(manager.effects) { info in
                        Button {
                            onSelect(info)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                PluginIcon(plugin: info)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(info.name).lineLimit(1)
                                    Text(info.manufacturerName)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Effect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { manager.scan() }
        }
    }
}
