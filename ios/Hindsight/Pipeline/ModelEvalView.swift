import SwiftUI

/// Beta menu → "Model test": runs `ModelEvalRunner` and shows the numbers.
struct ModelEvalView: View {
    @State private var runner = ModelEvalRunner()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sorts \(runner.cases.count) sample posts with Apple's models and compares them with the fixtures. Private Cloud Compute uses some of today's quota for this iCloud account.")
                        .font(Theme.body(15)).foregroundStyle(Theme.secondary)

                    section("Setup") {
                        if runner.probe.isEmpty {
                            Text("Checking…").foregroundStyle(Theme.secondary)
                        } else {
                            mono(runner.probe.joined(separator: "\n"))
                        }
                    }

                    ForEach(EvalEngine.allCases) { engine in
                        section(engine.title) {
                            if runner.running == engine {
                                ProgressView(value: Double(runner.done), total: Double(max(runner.cases.count, 1))).tint(Theme.lime)
                                Text("\(runner.done) of \(runner.cases.count)").font(Theme.body(14)).foregroundStyle(Theme.secondary)
                                Button("Stop") { runner.stop() }.buttonStyle(.pillCompact)
                            } else {
                                Button("Run") { runner.run(engine) }
                                    .buttonStyle(.pillCompact)
                                    .disabled(runner.running != nil)
                            }
                            if let summary = runner.summaries[engine] { mono(summary.report) }
                        }
                    }
                }
                .padding(Theme.padding)
            }
            .background(Theme.background)
            .navigationTitle("Model test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .task { await runner.runProbe() }
        // Keep the screen on: a run takes a few minutes.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.title(20))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }

    private func mono(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Theme.text)
            .textSelection(.enabled)
    }
}
