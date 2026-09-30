import Foundation
import FoundationModels

// What Apple's models are asked when sorting saves, and the shapes they answer
// in. Shared by the sort engine and the model test, so a test run measures the
// prompts the app actually uses. Bucket + places scored 86% / 57 of 70 on
// Private Cloud Compute (docs/merge-plan.md, E3 results).

@Generable enum SortScreen: String, CaseIterable {
    case map, learn, fitness, none

    var legoScreen: LegoScreen? { LegoScreen(rawValue: rawValue) }
}

@Generable struct SortBucket {
    @Guide(description: "One short sentence: what is this post, and would the person act on it (go somewhere, try something, do an exercise) or just enjoy it?")
    var reason: String
    var screen: SortScreen
    @Guide(description: "A short broad kebab-case topic slug, like nyc-food, guitar, ai-tools, back-mobility, memes")
    var topic: String
}

@Generable enum SortPlaceType: String {
    case food, cafe, bakery, bar, other
}

@Generable struct SortPlace {
    @Guide(description: "The place's name exactly as written in the text")
    var name: String
    @Guide(description: "food: restaurants and street food. cafe: coffee. bakery: bakeries and desserts. bar: bars and cocktails. other: anything else (parks, shops, sights, hotels)")
    var type: SortPlaceType
}

@Generable struct SortPlaces {
    @Guide(description: "Every specific venue named in the text (restaurant, cafe, bar, shop, beach, sight). Copy names exactly as written. Not cities, countries or neighborhoods on their own. Empty if none are named.", .maximumCount(12))
    var places: [SortPlace]
}

/// Topic naming: one call over every topic slug the posts got.
@Generable struct SortTopicPlan {
    @Guide(description: "The user's saves grouped into sections, like the sections of an app. Every input slug appears in exactly one topic.", .maximumCount(24))
    var topics: [SortPlannedTopic]
}

@Generable struct SortPlannedTopic {
    @Guide(description: "Short, human section name, 2-4 words, like 'NYC food & cafés', 'Guitar', 'Back & mobility'")
    var label: String
    @Guide(description: "One emoji for the section")
    var emoji: String
    @Guide(description: "The input slugs (exactly as given) that belong in this section")
    var slugs: [String]
    @Guide(description: "Only if it's genuinely unclear whether these posts are places to go or things to learn (e.g. 'Aesthetic coffee': cafés to visit, or coffee setups for home?): a short question to ask the user. Otherwise empty.")
    var question: String
}

@Generable enum SortTipType: String { case tool, technique, tutorial, list, idea }

@Generable struct SortTip {
    @Guide(description: "What the tip is, in at most 60 characters, in the caption's language. Not the raw caption.")
    var title: String
    @Guide(description: "What the tip is, in at most 140 characters. Empty if the caption doesn't say.")
    var gist: String
    @Guide(description: "One thing to try in about 2 minutes, imperative, at most 100 characters, based only on the caption. Empty if the caption doesn't say what the tip is. Never 'comment X on the post'.")
    var tryPrompt: String
    var tipType: SortTipType
    @Guide(description: "Only if the caption itself lists them, otherwise empty", .maximumCount(5))
    var keyPoints: [String]
}

@Generable enum SortBodyArea: String { case neck, shoulders, upperBack, lowerBack, hips, knees, ankles, core, fullBody }
@Generable enum SortGoal: String { case painRelief, mobility, posture, strength, recovery }
@Generable enum SortEquipment: String { case none, mat, band, foamRoller, dumbbell, other }

@Generable struct SortExercise {
    @Guide(description: "The exercise's name, as written in the caption")
    var name: String
    @Guide(description: "Reps if the caption states them, else 0")
    var reps: Int
    @Guide(description: "Sets if the caption states them, else 0")
    var sets: Int
    @Guide(description: "Hold time in seconds if the caption states it, else 0")
    var holdSeconds: Int
    var eachSide: Bool
}

@Generable struct SortRoutine {
    @Guide(description: "At most 40 characters, like 'Upper back release'")
    var title: String
    @Guide(.minimumCount(1))
    var bodyAreas: [SortBodyArea]
    var goal: SortGoal
    @Guide(description: "Only exercises listed in the caption; empty if the moves are only in the video")
    var exercises: [SortExercise]
    @Guide(description: "Minutes it takes if the caption says, else 0")
    var estMinutes: Int
    var equipment: [SortEquipment]
    @Guide(description: "One thing to do now, imperative, at most 100 characters, based only on the caption. Empty if the moves are only in the video.")
    var doPrompt: String
    var isPainRelated: Bool
}

enum SortPrompts {
    static let bucket = """
    You sort a person's saved social media posts for an app. Read the post and decide which screen it belongs to and a topic slug. Use only the given text.

    Examples:
    - "Best smash burger in the East Village 🍔 📍 @7thstreetburger" → map, nyc-food
    - "3 stretches for lower back pain, hold each 30s" → fitness, back-mobility
    - "This AI tool writes your emails for you. Comment AI for the link" → learn, ai-tools
    - "Easy protein pancakes: oats, eggs, banana" → learn, recipes
    - "POV: you said one more set 😂 #gymmemes" → none, memes
    - "Breaking: new iPhone announced today" → none, news
    - "Grateful for this weekend with my people ❤️" → none, personal
    A post only goes to learn if there is a concrete tip, technique, tool or recipe someone could try. Jokes, vibes, quotes and personal moments are none.
    """

    static let places = "You list the specific places named in a saved social media post, exactly as written. Never invent names. A city or neighborhood alone is not a place."

    static let topics = """
    You organize a person's saved posts into sections for their app. You get topic slugs with how many posts each has, which screen they're on, and a couple of example captions. Group slugs that belong together into broad sections (aim for 5-20), name each section the way a person would, and pick one emoji. Only group slugs from the same screen. Ask a question only when a section could clearly be either places to go or things to learn.
    """

    static let tip = "You summarize a saved tip or tutorial post for a practice app. Use only what the caption says; never invent steps or facts. Write in the caption's language."
    static let routine = "You summarize a saved stretch, mobility or workout post for a practice app. Use only what the caption says; never invent exercises or numbers."

    static func post(_ post: ContractPost) -> String {
        var text = "Author: @\(post.author.username)\n"
        if !post.collections.isEmpty { text += "Saved in the user's collection(s): \(post.collections.joined(separator: ", "))\n" }
        if !post.mentions.isEmpty { text += "Mentions: \(post.mentions.map { "@" + $0.username }.joined(separator: ", "))\n" }
        return text + "Caption:\n\((post.caption ?? "").prefix(1800))"
    }
}
