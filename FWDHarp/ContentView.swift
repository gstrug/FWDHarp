import SwiftUI

/// Placeholder until the chord pads and strum plate arrive.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
            Text("FWD Harp")
                .font(.largeTitle.bold())
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
