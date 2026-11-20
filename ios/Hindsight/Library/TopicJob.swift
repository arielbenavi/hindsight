import Foundation

/// What a topic is for. Decides where its saves come up (Today or not) and the
/// shape of its page (map, checklist, board, quiet shelf, list).
enum TopicJob: String, Codable, Sendable, CaseIterable, Identifiable {
    case go
    case doIt = "do"
    case learn
    case keepClose
    case look
    case know

    var id: String { rawValue }

    /// Library's section order.
    static let libraryOrder: [TopicJob] = [.go, .doIt, .learn, .keepClose, .look, .know]

    var title: String {
        switch self {
        case .go: "Go"
        case .doIt: "Do"
        case .learn: "Learn"
        case .keepClose: "Keep close"
        case .look: "Look"
        case .know: "Know"
        }
    }

    var symbol: String {
        switch self {
        case .go: "mappin.and.ellipse"
        case .doIt: "checklist"
        case .learn: "lightbulb.fill"
        case .keepClose: "heart.text.square.fill"
        case .look: "square.grid.2x2.fill"
        case .know: "books.vertical.fill"
        }
    }

    /// Library's one line under the section name: what it is, when it comes up.
    var whenLine: String {
        switch self {
        case .go: "places · on a map"
        case .doIt: "shows in Today until done"
        case .learn: "one tip a day in Today"
        case .keepClose: "private · only when you ask"
        case .look: "browse for ideas"
        case .know: "only when you search"
        }
    }

    /// The job picker's description.
    var pitch: String {
        switch self {
        case .keepClose: "A quiet shelf you open when you need it. Never in Today, never in a notification."
        case .doIt: "A list to work through. Shows up in Today until you mark it done."
        case .learn: "One tip a day, repeated until it sticks."
        case .go: "Places on a map. Comes up when you're nearby."
        case .look: "A board of pictures to browse for ideas."
        case .know: "Kept for reference. Only shows when you search."
        }
    }

    /// Its saves may come up in Today. Keep close / Look / Know never do.
    var allowsToday: Bool {
        switch self {
        case .go, .doIt, .learn: true
        case .keepClose, .look, .know: false
        }
    }

    /// Never in a notification, never a reminder.
    var isPrivate: Bool { self == .keepClose }
}

/// A topic's suggested job, from what it is. Pure and deterministic.
enum TopicJobs {
    /// The topic's view decides first (map → go, fitness → do, learn → learn), then
    /// words in its label. Notes ("Notes", a WhatsApp chat) are not guessed as
    /// Keep close: they stay Know until the user says otherwise.
    static func suggested(legoScreen: LegoScreen?, label: String) -> TopicJob {
        switch legoScreen {
        case .map: return .go
        case .fitness: return .doIt
        case .learn: return .learn
        case nil: break
        }
        let text = Words(label)
        for (job, keywords) in keywordTable where keywords.contains(where: text.has) { return job }
        return .know
    }

    static func suggested(for topic: HomeTopic) -> TopicJob {
        topic.kind == .other ? .know : suggested(legoScreen: topic.legoScreen, label: topic.label)
    }

    /// Checked in this order; the first job with a matching keyword wins. A
    /// keyword is a whole word, "stem*" a word start, "two words" a phrase.
    static let keywordTable: [(TopicJob, [String])] = [
        (.keepClose, ["mental health", "mental", "wellbeing", "well being", "wellness", "therapy", "therap*", "mindful*",
                      "meditat*", "self care", "selfcare", "self love", "motivation", "motivational", "affirmation*",
                      "healing", "journaling", "breathwork", "anxiety", "calm", "quotes", "reminders to self",
                      "בריאות הנפש", "נפש", "נפשית", "טיפול", "מיינדפולנס", "מדיטציה", "מוטיבציה", "חיזוקים",
                      "אהבה עצמית", "ריפוי", "רוגע", "השראה לנפש"]),
        (.go, ["travel*", "restaurant*", "cafe", "cafes", "café", "cafés", "places", "spots", "trip*", "bars", "eats",
               "nightlife", "things to do", "טיול*", "מסעדות", "מסעדה", "בתי קפה", "מקומות"]),
        (.doIt, ["food", "recipe*", "cooking", "cook", "baking", "workout*", "fitness", "exercise*", "stretch*", "diy",
                 "craft*", "to try", "things to try", "מתכון*", "מתכונ*", "בישול", "אוכל", "אימון*", "כושר"]),
        (.look, ["design*", "fashion", "style", "outfit*", "beauty", "makeup", "home", "interior*", "decor", "art",
                 "photography", "photo*", "tattoo*", "inspo", "inspiration", "aesthetic*",
                 "עיצוב", "אופנה", "סטייל", "אמנות", "צילום", "קעקוע*"]),
        (.learn, ["music production", "production", "guitar*", "instrument*", "piano", "coding", "code", "programming",
                  "study", "learning", "productivity", "languages", "language", "tips", "tutorial*", "lessons",
                  "הפקה", "גיטרה", "תכנות", "לימודים", "שפות", "טיפים"]),
    ]

    /// A label split into folded words, for keyword checks.
    struct Words {
        let tokens: [String]
        let joined: String

        init(_ label: String) {
            tokens = TextMatch.fold(label).split { !$0.isLetter && !$0.isNumber }.map(String.init)
            joined = " " + tokens.joined(separator: " ") + " "
        }

        func has(_ keyword: String) -> Bool {
            let folded = TextMatch.fold(keyword)
            if folded.contains(" ") { return joined.contains(" \(folded) ") }
            if folded.hasSuffix("*") {
                let stem = String(folded.dropLast())
                return tokens.contains { TopicFallback.variants($0).contains { $0.hasPrefix(stem) } }
            }
            // Hebrew one-letter prefixes ("למתכונים") come off, as in the lexicon.
            return tokens.contains { TopicFallback.variants($0).contains(folded) }
        }
    }
}
