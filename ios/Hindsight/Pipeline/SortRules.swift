import Foundation

/// The sort engine's deterministic parts: decisions that don't need a model,
/// checks on what a model said, and stand-ins until a model's details arrive.
enum SortRules {
    // MARK: - Certain decisions (no model call)

    /// Only near-certain cases: a location sticker or a 📍 line is a place post.
    /// Everything else goes to the model (the model beat broad rules: 86% vs 82%).
    static func certain(_ post: ContractPost) -> SortDecision? {
        if post.locationTag?.name?.nilIfEmpty != nil || (post.caption ?? "").contains("📍") {
            return SortDecision(screen: .map, slug: post.collections.first.map(slug) ?? "places")
        }
        return nil
    }

    /// When no model can answer: a place post if the rules say so, else Everything else.
    static func fallback(_ post: ContractPost) -> SortDecision {
        certain(post) ?? SortDecision(screen: nil, slug: "other")
    }

    // MARK: - Checking a model's places

    /// Keep only places whose name is actually in the post (caption, mentions or
    /// location sticker), with the evidence the confirmation cards highlight.
    static func places(_ found: [(name: String, type: PlaceType)], in post: ContractPost) -> [ExtractedPlace] {
        let caption = post.caption ?? ""
        let lines = caption.split(whereSeparator: \.isNewline).map(String.init)
        var seen = Set<String>()
        return found.compactMap { candidate in
            let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = TextMatch.fold(name)
            guard !name.isEmpty, seen.insert(key).inserted else { return nil }
            let tagName = post.locationTag?.name
            let mention = post.mentions.first { m in
                TextMatch.fold(m.username).contains(compact(key)) || m.displayName.map { TextMatch.fold($0) == key } == true
            }
            let kind: EvidenceKind
            let evidence: String
            if let tagName, TextMatch.fold(tagName) == key {
                kind = .locationTag; evidence = tagName
            } else if let line = lines.first(where: { $0.contains("📍") && TextMatch.fold($0).contains(key) }) {
                kind = .pinEmoji; evidence = String(line.prefix(120))
            } else if let mention {
                kind = .mention; evidence = "@\(mention.username)"
            } else if let range = caption.range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) {
                kind = .plainText; evidence = String(caption[range])
            } else {
                return nil  // not in the text: the model made it up or translated it
            }
            return ExtractedPlace(name: name, handle: mention?.username, areaHint: post.locationTag?.address,
                                  address: nil, type: candidate.type, reason: nil, evidence: evidence,
                                  evidenceKind: kind, confidence: kind.isStrong ? .high : .low)
        }
    }

    private static func compact(_ s: String) -> String { s.filter { $0.isLetter || $0.isNumber } }

    // MARK: - Stand-ins until the model's details land

    static func placeholderTip(_ post: ContractPost) -> ExtractedTip {
        ExtractedTip(title: String((post.firstLine ?? "Saved tip").prefix(60)), gist: nil, tryPrompt: nil,
                     tipType: .idea, keyPoints: [], ctaKeyword: ctaKeyword(post.caption), isThin: true)
    }

    static func placeholderRoutine(_ post: ContractPost) -> ExtractedRoutine {
        ExtractedRoutine(title: String((post.firstLine ?? "Saved routine").prefix(40)), bodyAreas: [.fullBody],
                         goal: .mobility, isThin: true)
    }

    /// "Comment DESIGN and I'll send you…" → "DESIGN".
    static func ctaKeyword(_ caption: String?) -> String? {
        guard let caption,
              let match = caption.firstMatch(of: /(?i)comment\s+["“”']?([A-Z0-9][A-Z0-9_-]{1,20})["“”']?/)
        else { return nil }
        let word = String(match.1)
        return word == word.uppercased() ? word : nil
    }

    // MARK: - Slugs

    /// "NYC Food!" → "nyc-food"
    static func slug(_ text: String) -> String {
        let parts = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        let s = parts.prefix(4).joined(separator: "-")
        return s.isEmpty ? "other" : s
    }

    /// "nyc-food" → "Nyc food"
    static func label(forSlug slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ").capitalizedFirst
    }

    /// "upperBack" → "upper_back" (the model's enum names → the contract's).
    static func snake(_ camel: String) -> String {
        camel.reduce(into: "") { out, c in
            if c.isUppercase { out += "_" + c.lowercased() } else { out.append(c) }
        }
    }
}
