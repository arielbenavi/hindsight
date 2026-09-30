import SwiftUI

/// Heights of the Map's bottom sheet (map.md → M1): peek, half, full.
enum SheetDetent: CaseIterable, Sendable {
    case peek, half, full

    func height(in total: CGFloat) -> CGFloat {
        switch self {
        case .peek: 168
        case .half: total * 0.5
        case .full: total - 24
        }
    }
}

/// A draggable panel over a full-screen map, like Find My. Stays inside the tab
/// (a system sheet would cover the tab bar).
struct BottomSheet<Content: View>: View {
    @Binding var detent: SheetDetent
    @ViewBuilder var content: Content

    @GestureState private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.height
            let height = max(SheetDetent.peek.height(in: total) - 40, detent.height(in: total) - drag)
            VStack(spacing: 0) {
                Capsule().fill(Theme.muted).frame(width: 40, height: 5).padding(.top, 8).padding(.bottom, 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                    .gesture(dragGesture(total: total))
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
            }
            .frame(height: height)
            .background(Theme.background.opacity(0.97), in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26).strokeBorder(Theme.stroke))
            .shadow(color: .black.opacity(0.4), radius: 18, y: -4)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .animation(.spring(duration: 0.35, bounce: 0.15), value: detent)
        }
    }

    private func dragGesture(total: CGFloat) -> some Gesture {
        DragGesture()
            .updating($drag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                let projected = detent.height(in: total) - value.predictedEndTranslation.height
                detent = SheetDetent.allCases.min { abs($0.height(in: total) - projected) < abs($1.height(in: total) - projected) } ?? detent
            }
    }
}
