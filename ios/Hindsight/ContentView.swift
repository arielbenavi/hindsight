import SwiftUI

// Placeholder screen: confirms the app builds and the seed data is bundled.
struct ContentView: View {
    private let savedPostCount = SeedData.savedPostCount()

    var body: some View {
        VStack(spacing: 8) {
            Text("Hindsight")
                .font(.largeTitle.bold())
            Text("\(savedPostCount) saved posts in seed data")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
