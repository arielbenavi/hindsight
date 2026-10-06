import Foundation
import FoundationModels
import Observation

/// On-phone test of Apple's models for sorting saves (ADR-001, E3): the same
/// ~115 fixture posts through the on-device model and Private Cloud Compute,
/// scored against the fixtures' labels. Answers what a Mac can't: Hebrew on
/// Private Cloud Compute, the iPhone's on-device model, speed, and the quota.
/// Mac baseline (2026-09-30, macOS 26.6 model): 70% buckets, 29/71 place names.
enum EvalEngine: String, CaseIterable, Codable, Sendable, Identifiable {
    case onDevice = "on-device"
    case cloud = "private-cloud-compute"
    var id: String { rawValue }
    var title: String { self == .onDevice ? "On-device" : "Private Cloud Compute" }
}

/// One post to sort, with the fixture's answer.
struct EvalCase: Sendable {
    let post: ContractPost
    let dataset: String
    /// The fixture's lego screen; nil = none (Everything else).
    let gold: LegoScreen?
    let goldPlaces: [String]
    var isHebrew: Bool { post.caption?.unicodeScalars.contains { (0x0590...0x05FF).contains($0.value) } ?? false }

    /// The same stratified sample as the Mac test: Reut 25 map / 15 learn / 15 none,
    /// Ariel 20 learn / 10 fitness / 10 map / 20 none, spread evenly through each file.
    static func sample(from datasets: [Dataset]) -> [EvalCase] {
        let quotas: [String: [(LegoScreen?, Int)]] = [
            "reut": [(.map, 25), (.learn, 15), (nil, 15)],
            "ariel": [(.learn, 20), (.fitness, 10), (.map, 10), (nil, 20)],
        ]
        var cases: [EvalCase] = []
        for dataset in datasets {
            guard let quota = quotas[dataset.id], let data = try? HindsightData.load(from: dataset.url) else { continue }
            for (screen, count) in quota {
                let pool = data.posts.filter { data.topic(forPost: $0.id)?.legoScreen == screen }
                guard !pool.isEmpty else { continue }
                let step = max(1, pool.count / count)
                for post in stride(from: 0, to: pool.count, by: step).prefix(count).map({ pool[$0] }) {
                    let places = data.item(for: post.id)?.places?.map(\.name) ?? []
                    cases.append(EvalCase(post: post, dataset: dataset.id, gold: screen, goldPlaces: places))
                }
            }
        }
        return cases
    }
}

// The prompts and schemas live in SortPrompts.swift, shared with the sort engine.

// MARK: - Results

struct EvalRow: Codable, Sendable {
    var id: String
    var dataset: String
    var gold: String
    var hebrew: Bool
    var screen: String?
    var places: [String] = []
    var goldPlaces: [String]
    var error: String?
    var seconds: Double
    /// Tokens this post cost (both requests), from `LanguageModelSession.usage`.
    var inputTokens = 0
    var outputTokens = 0
}

struct EvalSummary: Codable, Sendable {
    var engine: EvalEngine
    var rows: [EvalRow]
    var stoppedForQuota = false
    var quotaAfter: String?

    var answered: [EvalRow] { rows.filter { $0.screen != nil } }
    var correct: Int { answered.count { $0.screen == $0.gold } }
    var errors: [String: Int] { Dictionary(grouping: rows.compactMap(\.error), by: { $0 }).mapValues(\.count) }
    var hebrew: (correct: Int, answered: Int, total: Int) {
        let rows = rows.filter(\.hebrew)
        let answered = rows.filter { $0.screen != nil }
        return (answered.count { $0.screen == $0.gold }, answered.count, rows.count)
    }
    /// Gold place names found (loose match, as on the Mac), over map posts.
    var placeRecall: (found: Int, total: Int) {
        var found = 0, total = 0
        for row in answered where row.gold == "map" {
            for gold in row.goldPlaces {
                total += 1
                let g = Self.norm(gold)
                if row.places.contains(where: { let p = Self.norm($0); return !p.isEmpty && (p.contains(g) || g.contains(p)) }) { found += 1 }
            }
        }
        return (found, total)
    }
    var tokens: (input: Int, output: Int) { (rows.reduce(0) { $0 + $1.inputTokens }, rows.reduce(0) { $0 + $1.outputTokens }) }

    var medianSeconds: Double {
        let s = answered.map(\.seconds).sorted()
        return s.isEmpty ? 0 : s[s.count / 2]
    }
    /// gold → answer → count
    var confusion: [String: [String: Int]] {
        var m: [String: [String: Int]] = [:]
        for row in answered { m[row.gold, default: [:]][row.screen ?? "?", default: 0] += 1 }
        return m
    }

    private static func norm(_ s: String) -> String { String(s.lowercased().filter { $0.isLetter || $0.isNumber }) }

    var report: String {
        var lines = ["\(engine.title): \(correct)/\(answered.count) buckets (\(answered.isEmpty ? 0 : 100 * correct / answered.count)%), \(rows.count - answered.count) errors \(errors)"]
        let h = hebrew
        lines.append("  Hebrew: \(h.answered)/\(h.total) answered, \(h.correct) correct")
        let p = placeRecall
        lines.append("  Place names: \(p.found)/\(p.total) · median \(String(format: "%.1f", medianSeconds)) s/post")
        let t = tokens
        let perPost = rows.isEmpty ? 0 : (t.input + t.output) / rows.count
        lines.append("  Tokens: \(t.input.formatted()) in + \(t.output.formatted()) out · ~\(perPost) per post")
        for gold in ["map", "learn", "fitness", "none"] { lines.append("  \(gold) → \(confusion[gold] ?? [:])") }
        if stoppedForQuota { lines.append("  ⚠️ stopped: quota reached") }
        if let quotaAfter { lines.append("  quota after: \(quotaAfter)") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Runner

@Observable
@MainActor
final class ModelEvalRunner {
    let cases: [EvalCase]
    private(set) var probe: [String] = []
    private(set) var running: EvalEngine?
    private(set) var done = 0
    private(set) var summaries: [EvalEngine: EvalSummary] = [:]
    private var task: Task<Void, Never>?

    init(datasets: [Dataset] = Dataset.bundled()) {
        cases = EvalCase.sample(from: datasets)
    }

    /// Availability, languages (Hebrew?), context size and quota, with no generation.
    func runProbe() async {
        var lines: [String] = []
        let local = SystemLanguageModel.default
        if #available(iOS 27, *) {
            lines.append("On-device: \(local.availability) · model: \(local.variant.displayName)")
        } else {
            lines.append("On-device: \(local.availability)")
        }
        lines.append("  Hebrew: \(local.supportsLocale(Locale(identifier: "he_IL")) ? "yes" : "no") · context \(local.contextSize) tokens")
        lines.append("  languages: \(Self.codes(local.supportedLanguages))")
        if #available(iOS 27, *) {
            let cloud = PrivateCloudComputeLanguageModel()
            lines.append("Private Cloud Compute: \(cloud.availability)")
            do {
                let hebrew = try await cloud.supportsLocale(Locale(identifier: "he_IL"))
                let context = try await cloud.contextSize
                lines.append("  Hebrew: \(hebrew ? "yes" : "no") · context \(context) tokens")
                lines.append("  languages: \(Self.codes(try await cloud.supportedLanguages))")
            } catch {
                lines.append("  couldn't read languages: \(error)")
            }
            lines.append("  quota: \(Self.describe(cloud.quotaUsage))")
        } else {
            lines.append("Private Cloud Compute: needs iOS 27")
        }
        probe = lines
        DebugLog.write("model eval probe\n" + lines.joined(separator: "\n"))
    }

    func run(_ engine: EvalEngine) {
        guard running == nil else { return }
        running = engine
        done = 0
        task = Task {
            var summary = EvalSummary(engine: engine, rows: [])
            for c in cases {
                if Task.isCancelled { break }
                let row = await Self.sort(c, engine: engine)
                summary.rows.append(row)
                done += 1
                summaries[engine] = summary
                if row.error?.hasPrefix("quotaLimitReached") == true { summary.stoppedForQuota = true; break }
            }
            if #available(iOS 27, *), engine == .cloud { summary.quotaAfter = Self.describe(PrivateCloudComputeLanguageModel().quotaUsage) }
            summaries[engine] = summary
            running = nil
            Self.save(summary)
        }
    }

    func stop() { task?.cancel() }

    private static func sort(_ c: EvalCase, engine: EvalEngine) async -> EvalRow {
        var row = EvalRow(id: c.post.id, dataset: c.dataset, gold: c.gold?.rawValue ?? "none", hebrew: c.isHebrew,
                          goldPlaces: c.goldPlaces, seconds: 0)
        let prompt = SortPrompts.post(c.post)
        let start = ContinuousClock.now
        do {
            guard let session = session(engine, instructions: SortPrompts.bucket) else { throw EvalUnavailable() }
            defer { count(session, into: &row) }
            let bucket = try await session.respond(to: prompt, generating: SortBucket.self, options: GenerationOptions(sampling: .greedy))
            row.screen = bucket.content.screen.rawValue
            if bucket.content.screen == .map, let places = self.session(engine, instructions: SortPrompts.places) {
                defer { count(places, into: &row) }
                let found = try await places.respond(to: prompt, generating: SortPlaces.self, options: GenerationOptions(sampling: .greedy))
                row.places = found.content.places.map(\.name)
            }
        } catch {
            row.error = String(String(describing: error).prefix { $0 != "(" })
        }
        let elapsed = ContinuousClock.now - start
        row.seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return row
    }

    private static func session(_ engine: EvalEngine, instructions: String) -> LanguageModelSession? {
        switch engine {
        case .onDevice:
            return LanguageModelSession(model: SystemLanguageModel.default, instructions: Instructions(instructions))
        case .cloud:
            guard #available(iOS 27, *) else { return nil }
            return LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: Instructions(instructions))
        }
    }

    private struct EvalUnavailable: Error {}

    /// Token usage is iOS 27+; on iOS 26 the counts stay 0.
    private static func count(_ session: LanguageModelSession, into row: inout EvalRow) {
        guard #available(iOS 27, *) else { return }
        row.inputTokens += session.usage.input.totalTokenCount
        row.outputTokens += session.usage.output.totalTokenCount
    }

    private static func codes(_ languages: Set<Locale.Language>) -> String {
        Set(languages.compactMap { $0.languageCode?.identifier }).sorted().joined(separator: " ")
    }

    @available(iOS 27, *)
    private static func describe(_ usage: PrivateCloudComputeLanguageModel.QuotaUsage) -> String {
        let reset = usage.resetDate.map { " (resets \($0.formatted(date: .abbreviated, time: .shortened)))" } ?? ""
        switch usage.status {
        case .belowLimit(let below): return (below.isApproachingLimit ? "approaching the limit" : "below the limit") + reset
        case .limitReached: return "limit reached" + reset
        @unknown default: return "unknown" + reset
        }
    }

    /// `Application Support/model-eval-<engine>.json` + the debug log, so the
    /// results can be pulled off the phone (scripts/device.sh log).
    private static func save(_ summary: EvalSummary) {
        DebugLog.write("model eval\n" + summary.report)
        let url = URL.applicationSupportDirectory.appending(path: "model-eval-\(summary.engine.rawValue).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try? encoder.encode(summary).write(to: url, options: .atomic)
    }
}
