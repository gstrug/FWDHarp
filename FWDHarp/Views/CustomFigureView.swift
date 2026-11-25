import SwiftUI

/// Edits the Custom plate order's figure (Graham, 2026-11-25): steps of the chord —
/// 1, 3, 5, 7 and 8 (the octave) — played in that order and repeated up the plate.
/// Starts as 1 3 5. Choosing it here also sets the plate to Custom.
struct CustomFigureView: View {
    @ObservedObject var player: HarpPlayer
    @Environment(\.dismiss) private var dismiss

    private var figure: [Int] { player.customPlateFigure }

    private func set(_ new: [Int]) {
        player.setCustomPlateFigure(new)
        if player.platePattern != .custom { player.setPlatePattern(.custom) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        ForEach(Array(figure.enumerated()), id: \.offset) { _, step in
                            Text("\(step)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioStyle.displayText)
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Figure: \(PlatePattern.describe(figure))")
                } header: {
                    Text("Figure")
                } footer: {
                    Text("Played up the plate in this order, then again an octave of chord notes higher, to the top string.")
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
                        .disabled(figure.count <= PlatePattern.customLength.lowerBound)
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
