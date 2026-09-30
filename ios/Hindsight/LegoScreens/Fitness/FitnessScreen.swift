import SwiftUI

/// Fitness tab root (F1). Placeholder until the real screen lands.
struct FitnessScreen: View {
    let app: AppModel
    let tab: TabConfig

    var body: some View {
        Text(tab.title).font(Theme.title())
    }
}
