import SwiftUI

/// Learn tab root (L1). Placeholder until the real screen lands.
struct LearnScreen: View {
    let app: AppModel
    let tab: TabConfig

    var body: some View {
        Text(tab.title).font(Theme.title())
    }
}
