import Foundation
import FoundationModels

/// What the sort engine asks a model. Plain values in and out, so tests can
/// swap in a fake without Apple Intelligence.
protocol SortBackend: Sendable {
    /// Bucket + topic slug for one post. nil when no model can answer (the
    /// engine falls back to rules / Everything else).
    func bucket(_ post: ContractPost) async -> SortDecision?
    /// Places named in a map post (names as written + type).
    func places(_ post: ContractPost) async -> [(name: String, type: PlaceType)]?
    /// Group slugs into named topics. nil → the engine names them itself.
    func topics(_ hints: [TopicHint]) async -> [PlannedTopic]?
    func tip(_ post: ContractPost) async -> ExtractedTip?
    func routine(_ post: ContractPost) async -> ExtractedRoutine?
    /// Tokens used so far and which model answered, for the usage record.
    func usage() async -> SortUsage
}

struct SortDecision: Codable, Sendable, Hashable {
    /// nil = none (Everything else).
    var screen: LegoScreen?
    var slug: String
}

/// One (screen, slug) group of posts, as shown to the topic-naming call.
struct TopicHint: Sendable, Hashable {
    var screen: LegoScreen?
    var slug: String
    var count: Int
    var samples: [String]
    var collections: [String]
}

struct PlannedTopic: Sendable, Hashable {
    var label: String
    var emoji: String
    var slugs: [String]
    var question: String?
}

struct SortUsage: Codable, Sendable, Equatable {
    var inputTokens = 0
    var outputTokens = 0
    var cloudRequests = 0
    var onDeviceRequests = 0
    var failedRequests = 0
    /// Last Private Cloud Compute quota status we saw.
    var quota: String?
}

/// Apple's models: Private Cloud Compute first (iOS 27, entitlement, quota
/// left), then the on-device model, per request. A request that fails on the
/// cloud (guardrail, network, quota) is retried on-device once.
actor AppleSortBackend: SortBackend {
    private var tally = SortUsage()
    private var cloudExhausted = false

    func bucket(_ post: ContractPost) async -> SortDecision? {
        guard let answer = await ask(SortPrompts.bucket, SortPrompts.post(post), SortBucket.self) else { return nil }
        return SortDecision(screen: answer.screen.legoScreen, slug: SortRules.slug(answer.topic))
    }

    func places(_ post: ContractPost) async -> [(name: String, type: PlaceType)]? {
        guard let answer = await ask(SortPrompts.places, SortPrompts.post(post), SortPlaces.self) else { return nil }
        return answer.places.map { ($0.name, PlaceType(rawValue: $0.type.rawValue) ?? .other) }
    }

    func topics(_ hints: [TopicHint]) async -> [PlannedTopic]? {
        let lines = hints.map { hint in
            var line = "- \(hint.slug) [\(hint.screen?.rawValue ?? "none")] \(hint.count) posts"
            if !hint.collections.isEmpty { line += " · collections: \(hint.collections.prefix(3).joined(separator: ", "))" }
            for sample in hint.samples.prefix(2) { line += "\n    \"\(sample.prefix(120))\"" }
            return line
        }
        // Only the cloud model has room for every slug (32K context vs 4K).
        guard let answer = await ask(SortPrompts.topics, "Topic slugs:\n" + lines.joined(separator: "\n"), SortTopicPlan.self, cloudOnly: true)
        else { return nil }
        return answer.topics.map {
            PlannedTopic(label: $0.label, emoji: $0.emoji, slugs: $0.slugs, question: $0.question.isEmpty ? nil : $0.question)
        }
    }

    func tip(_ post: ContractPost) async -> ExtractedTip? {
        guard let t = await ask(SortPrompts.tip, SortPrompts.post(post), SortTip.self) else { return nil }
        let cta = SortRules.ctaKeyword(post.caption)
        return ExtractedTip(title: String(t.title.prefix(60)), gist: t.gist.nilIfEmpty.map { String($0.prefix(140)) },
                            tryPrompt: t.tryPrompt.nilIfEmpty.map { String($0.prefix(100)) },
                            tipType: TipType(rawValue: t.tipType.rawValue) ?? .idea, keyPoints: Array(t.keyPoints.prefix(5)),
                            ctaKeyword: cta, isThin: t.gist.isEmpty && t.tryPrompt.isEmpty)
    }

    func routine(_ post: ContractPost) async -> ExtractedRoutine? {
        guard let r = await ask(SortPrompts.routine, SortPrompts.post(post), SortRoutine.self) else { return nil }
        let areas = r.bodyAreas.compactMap { BodyArea(rawValue: SortRules.snake($0.rawValue)) }
        return ExtractedRoutine(
            title: String(r.title.prefix(40)), bodyAreas: areas.isEmpty ? [.fullBody] : areas,
            goal: FitnessGoal(rawValue: SortRules.snake(r.goal.rawValue)) ?? .mobility,
            exercises: r.exercises.map { Exercise(name: $0.name, reps: $0.reps.positive, sets: $0.sets.positive,
                                                  holdSeconds: $0.holdSeconds.positive, eachSide: $0.eachSide) },
            estMinutes: r.estMinutes.positive,
            equipment: r.equipment.compactMap { Equipment(rawValue: SortRules.snake($0.rawValue)) },
            doPrompt: r.doPrompt.nilIfEmpty.map { String($0.prefix(100)) },
            isThin: r.exercises.isEmpty && r.doPrompt.isEmpty, isPainRelated: r.isPainRelated)
    }

    func usage() async -> SortUsage { tally }

    // MARK: - Requests

    private func ask<T: Generable>(_ instructions: String, _ prompt: String, _ type: T.Type, cloudOnly: Bool = false) async -> T? {
        if #available(iOS 27, *), !cloudExhausted {
            let cloud = PrivateCloudComputeLanguageModel()
            if cloud.isAvailable {
                let session = LanguageModelSession(model: cloud, instructions: Instructions(instructions))
                do {
                    let response = try await session.respond(to: prompt, generating: T.self, options: GenerationOptions(sampling: .greedy))
                    record(session, cloud: true)
                    return response.content
                } catch {
                    tally.failedRequests += 1
                    if case PrivateCloudComputeLanguageModel.Error.quotaLimitReached = error { cloudExhausted = true }
                    DebugLog.write("sort: cloud failed (\(String(describing: error).prefix(80)))")
                }
                tally.quota = Self.describe(cloud.quotaUsage)
            }
        }
        guard !cloudOnly, SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: Instructions(instructions))
        do {
            let response = try await session.respond(to: prompt, generating: T.self, options: GenerationOptions(sampling: .greedy))
            record(session, cloud: false)
            return response.content
        } catch {
            tally.failedRequests += 1
            return nil
        }
    }

    private func record(_ session: LanguageModelSession, cloud: Bool) {
        if cloud { tally.cloudRequests += 1 } else { tally.onDeviceRequests += 1 }
        if #available(iOS 27, *) {
            tally.inputTokens += session.usage.input.totalTokenCount
            tally.outputTokens += session.usage.output.totalTokenCount
        }
    }

    @available(iOS 27, *)
    private static func describe(_ usage: PrivateCloudComputeLanguageModel.QuotaUsage) -> String {
        switch usage.status {
        case .belowLimit(let below): below.isApproachingLimit ? "approaching" : "below"
        case .limitReached: "reached"
        @unknown default: "unknown"
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

private extension Int {
    var positive: Int? { self > 0 ? self : nil }
}
