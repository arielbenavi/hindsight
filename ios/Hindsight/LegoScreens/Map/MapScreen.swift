import SwiftUI

/// Map tab root (M1). Placeholder until the real screen lands.
struct MapScreen: View {
    let app: AppModel
    let tab: TabConfig

    var body: some View {
        Text(tab.title).font(Theme.title())
    }
}
