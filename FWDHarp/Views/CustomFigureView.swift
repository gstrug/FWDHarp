import SwiftUI

/// Edits the Custom plate order's figure (Graham, 2026-11-25): steps of the chord —
/// 1, 3, 5, 7 and 8 (the octave) — played in that order and repeated up the plate.
/// Starts as 1 3 5. Choosing it here also sets the plate to Custom.
struct CustomFigureView: View {
    @ObservedObject var player: HarpPlayer
    @Environment(\.dismiss) private var dismiss

    /// The figure being written. It may be emptied to start again (Graham, 2026-11-25:
    /// the first step could never be removed, so 5 3 1 could not be written); the
    /// plate keeps playing the last figure with a step in it.
    @State private var figure: [Int] = []
    @State private var loaded = false

    private func set(_ new: [Int]) {
        figure = new
        guard !new.isEmpty else { return }
        player.setCustomPlateFigure(new)
        if player.platePattern != .custom { player.setPlatePattern(.custom) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        if figure.isEmpty {
                            Text("Empty: add the first step below")
                                .foregroundStyle(StudioStyle.scaleText)
                                .frame(height: 44)
                        }
                        // Tap a step to take it out.
                        ForEach(Array(figure.enumerated()), id: \.offset) { index, step in
                            Button {
                                var copy = figure
                                copy.remove(at: index)
                                set(copy)
                            } label: {
                                Text("\(step)")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(StudioStyle.displayText)
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        Button("Clear") { set([]) }
                            .disabled(figure.isEmpty)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Figure")
                } footer: {
                    Text("Tap a step to take it out, or Clear to start again. The first step is the lowest note; any step below it is played an octave up, so 5 1 3 and 3 5 1 are inversions. The figure then repeats an octave higher, to the top string.")
                }

                Section {
                    HStack(spacing: 10) {
                        ForEach(PlatePattern.customSteps, id: \.self) { step in
                            Button("\(step)") { set(figure + [step]) }
                                .font(.system(size: 20, weight: .bold))
                                .frame(width: 48, height: 44)
                                .buttonStyle(.bordered)
                                .disabled(figure.count >= PlatePattern.customLength.upperBound)
                                .accessibilityLabel("Add \(name(step))")
                        }
                        Spacer()
                        Button { set(Array(figure.dropLast())) } label: {
                            Image(systemName: "delete.left").font(.system(size: 20))
                        }
                        .frame(width: 48, height: 44)
                        .buttonStyle(.bordered)
                        .disabled(figure.isEmpty)
                        .accessibilityLabel("Remove the last step")
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Add a step")
                } footer: {
                    Text("1 the root, 3 the third, 5 the fifth, 7 the seventh (the octave on chords without one), 8 the octave. Up to eight steps.")
                }

                Section {
                    Button("Reset to 1 3 5") { set(PlatePattern.defaultCustom) }
                }
            }
            .onAppear {
                if !loaded { figure = player.customPlateFigure; loaded = true }
            }
            .navigationTitle("Custom Plate Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func name(_ step: Int) -> String {
        switch step {
        case 1: return "the root"
        case 3: return "the third"
        case 5: return "the fifth"
        case 7: return "the seventh"
        default: return "the octave"
        }
    }
}
