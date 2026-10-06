import Foundation
import Testing
@testable import Hindsight

@MainActor
struct LearnTests {
    func catalog(_ id: String) throws -> LearnCatalog {
        let data = try Fixtures.load(id)
        let layout = LayoutRules.propose(data).draft
        return LearnCatalog(data: data, topicIDs: layout.tab(for: .learn)?.topicIDs ?? [])
    }

    @Test func searchFindsDiminished() throws {
        let tips = try catalog("ariel").tips
        let hits = TipSearch.search("DIMINISHED", in: tips)
        #expect(hits.first?.title.lowercased().contains("diminished") == true)
    }

    @Test func titleMatchesRankAboveCaptionMatches() {
        let post1 = ContractPost(id: "instagram:a", url: URL(string: "https://www.instagram.com/p/a/")!, author: "a", caption: "nothing here")
        let post2 = ContractPost(id: "instagram:b", url: URL(string: "https://www.instagram.com/p/b/")!, author: "b", caption: "a bossa groove")
        let t1 = Tip(post: post1, topicID: "g", extracted: ExtractedTip(title: "Bossa nova chords", gist: nil, tryPrompt: "Play it.", tipType: .technique, keyPoints: [], ctaKeyword: nil, isThin: false))
        let t2 = Tip(post: post2, topicID: "g", extracted: ExtractedTip(title: "Groove basics", gist: nil, tryPrompt: "Play it.", tipType: .technique, keyPoints: [], ctaKeyword: nil, isThin: false))
        #expect(TipSearch.search("bossa", in: [t2, t1]).map(\.id) == ["instagram:a", "instagram:b"])
    }

    @Test func searchIsAccentInsensitiveAndHandlesHebrew() throws {
        let tips = try catalog("reut").tips
        #expect(!TipSearch.search("חומוס", in: tips).isEmpty)
        let post = ContractPost(id: "instagram:c", url: URL(string: "https://www.instagram.com/p/c/")!, author: "c", caption: nil)
        let t = Tip(post: post, topicID: "x", extracted: ExtractedTip(title: "Café crème", gist: nil, tryPrompt: nil, tipType: .idea, keyPoints: [], ctaKeyword: nil, isThin: true))
        #expect(TipSearch.search("cafe creme", in: [t]).count == 1)
    }

    @Test func reutHasAGuitarSectionWithTryPrompts() throws {
        let learn = try catalog("reut")
        let guitar = try #require(learn.section("guitar"))
        #expect(guitar.tips.contains { $0.tryPrompt != nil })
    }

    @Test func commentForTheLinkPostsKeepTheirKeyword() throws {
        let tips = try catalog("ariel").tips
        let cta = try #require(tips.first { $0.ctaKeyword == "DESIGN" })
        #expect(cta.isGated)
    }

    @Test func commentForTheGuidePostsAreGatedNotPracticed() throws {
        let post = ContractPost(id: "instagram:g", url: URL(string: "https://www.instagram.com/p/g/")!, author: "g",
                                caption: "Comment GUIDE and I'll send you my 5 tools")
        let gated = Tip(post: post, topicID: "ai", extracted: ExtractedTip(
            title: "5 AI tools", gist: nil, tryPrompt: "Comment GUIDE on the post to get the tools.",
            tipType: .list, keyPoints: [], ctaKeyword: "GUIDE", isThin: false))
        #expect(gated.isGated)
        #expect(!gated.isPickable)
        #expect(gated.prompt == nil)
        // with the key points in the caption, it's a real tip, but "comment X" is never the prompt
        let withPoints = Tip(post: post, topicID: "ai", extracted: ExtractedTip(
            title: "5 AI tools", gist: nil, tryPrompt: "Open Figma AI and make one screen.", tipType: .list,
            keyPoints: ["Figma AI", "v0"], ctaKeyword: "GUIDE", isThin: false))
        #expect(!withPoints.isGated)
        #expect(withPoints.isPickable)
        for tip in try catalog("ariel").tips + catalog("reut").tips where tip.isPickable {
            #expect(!Tip.isCommentInstruction(tip.prompt ?? "", keyword: tip.ctaKeyword))
        }
    }

    @Test func thinTipsAreNeverPickable() throws {
        for tip in try catalog("ariel").tips where tip.isThin { #expect(!tip.isPickable) }
    }
}

@MainActor
struct FitnessTests {
    func catalog() throws -> FitnessCatalog {
        let data = try Fixtures.load("ariel")
        return FitnessCatalog(data: data, topicIDs: LayoutRules.propose(data).draft.tab(for: .fitness)?.topicIDs ?? [])
    }

    @Test func problemSearchSynonyms() {
        #expect(ProblemSearch.interpret("my back hurts")?.areas == [.lowerBack])
        #expect(ProblemSearch.interpret("tech neck")?.areas == [.neck])
        #expect(ProblemSearch.interpret("desk posture")?.goal == .posture)
        #expect(ProblemSearch.interpret("guitar") == nil)
    }

    @Test func arielHasAFitnessTabWithHisRoutines() throws {
        let c = try catalog()
        #expect(c.routines.count >= 10)
        #expect(!c.areas.isEmpty)
        #expect(c.areas.allSatisfy { $0.count > 0 })
    }

    @Test func backPainSearchFindsLowerBackRoutines() throws {
        let c = try catalog()
        let hits = ProblemSearch.search("back hurts", in: c.routines)
        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { $0.info.bodyAreas.contains(.lowerBack) })
        #expect(!ProblemSearch.search("desk posture", in: c.routines).isEmpty)
    }

    @Test func thinRoutinesAreFollowAlongAndPickable() throws {
        let c = try catalog()
        let thin = try #require(c.routines.first { $0.info.isThin })
        #expect(thin.prompt.hasPrefix("Follow along"))
        #expect(c.candidates.allSatisfy { $0.isPickable })
    }

    @Test func gymMemesAreNotFitnessAndPainRoutinesGetTheNote() throws {
        let data = try Fixtures.load("ariel")
        let memes = data.topics.filter { $0.legoScreen == nil }.flatMap(\.postIds)
        let routines = try catalog().routines
        #expect(Set(routines.map(\.id)).isDisjoint(with: memes))
        #expect(routines.contains { $0.info.isPainRelated })
    }
}
