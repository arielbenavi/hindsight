import SwiftUI

struct PreferencesStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingPage {
            Text("How do you\nwant to see it?")
                .font(OnboardingStyle.display(40))
                .minimumScaleFactor(0.7)

            section("Group my saves") {
                FlowLayout(spacing: 8) {
                    ForEach(OnboardingPreferences.Grouping.allCases) { grouping in
                        OnboardingChip(label: grouping.title, isSelected: model.preferences.grouping == grouping) {
                            model.preferences.grouping = grouping
                        }
                    }
                }
            }

            section("Layout") {
                HStack(spacing: 10) {
                    ForEach(OnboardingPreferences.Layout.allCases) { layout in
                        layoutTile(layout)
                    }
                }
            }

            section("Topics I care about") {
                FlowLayout(spacing: 8) {
                    ForEach(model.topicSuggestions, id: \.topic) { suggestion in
                        OnboardingChip(
                            label: suggestion.topic,
                            detail: suggestion.count.formatted(),
                            isSelected: model.preferences.topics.contains(suggestion.topic)
                        ) {
                            model.toggleTopic(suggestion.topic)
                        }
                    }
                }
                Text("Counts are from your saves.")
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(OnboardingStyle.muted)
            }

            section("Bring old saves back") {
                HStack(spacing: 8) {
                    ForEach(OnboardingPreferences.Resurface.allCases) { cadence in
                        OnboardingChip(label: cadence.title, isSelected: model.preferences.resurface == cadence) {
                            model.preferences.resurface = cadence
                        }
                    }
                }
            }
        } actions: {
            Button("Looks good", action: model.next)
                .buttonStyle(.onboardingPrimary)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(OnboardingStyle.muted)
            content()
        }
    }

    private func layoutTile(_ layout: OnboardingPreferences.Layout) -> some View {
        let isSelected = model.preferences.layout == layout
        return Button {
            model.preferences.layout = layout
        } label: {
            VStack(spacing: 8) {
                Image(systemName: layout.symbol).font(.system(size: 26, weight: .semibold))
                Text(layout.title).font(OnboardingStyle.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .foregroundStyle(isSelected ? OnboardingStyle.onAccent : OnboardingStyle.text)
            .background(isSelected ? OnboardingStyle.accent : OnboardingStyle.surface, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(isSelected ? .clear : OnboardingStyle.stroke))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// Wraps children onto new lines when they run out of width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .init(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : spacing + size.width
            if rows[rows.count - 1].width + extra > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
                rows[rows.count - 1].indices = [index]
                rows[rows.count - 1].width = size.width
                rows[rows.count - 1].height = size.height
            } else {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width += extra
                rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            }
        }
        return rows
    }
}
