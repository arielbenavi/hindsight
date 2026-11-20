import Foundation

/// Topics without a model: what the sort engine uses for a post no model
/// answered (simulator, phones without Apple Intelligence, quota spent, a
/// refused caption). Deterministic and on-device. Signals, strongest first:
///
/// 1. the user's own collection on the post ("NYC Restaurants", a WhatsApp chat)
/// 2. hashtags, 3. caption words — scored against `lexicon`
/// 4. the author's other saves, when most of them landed in one topic
/// 5. the platform (WhatsApp notes → "Notes", X → "Posts from X")
///
/// Only posts with none of these end up in "Other". It only picks the topic;
/// screens stay the rules' job (`SortRules`).
enum TopicFallback {
    struct Topic: Sendable {
        var id: String
        var label: String
        var symbol: String
        var emoji: String
        /// Caption words, matched as whole tokens (plus -s/-es). "stem*" matches
        /// any token starting with stem; "two words" a phrase; "😂" anywhere.
        /// "~word" is ambiguous on its own ("love", "photo"): half weight in a
        /// caption, so it needs a second word to count. Hashtags weigh in full.
        var words: [String]
        /// Hashtag stems: whole tag, or start/end of one (4+ letters), or
        /// anywhere in it (5+): "guitar" hits #guitartutorial, "art" never hits #start.
        var tags: [String] = []
    }

    enum Signal: Int, Comparable, Sendable {
        case collection, hashtag, caption, author, platform

        static func < (a: Signal, b: Signal) -> Bool { a.rawValue < b.rawValue }
    }

    struct Pick: Sendable, Hashable {
        var slug: String
        var label: String
        var signal: Signal
    }

    /// The leftover topic, for posts with no signal at all.
    static let otherSlug = "other"

    // MARK: - Assigning

    /// A topic for every post that has any signal; posts missing from the result
    /// have none ("Other"). Needs all posts at once for the author signal.
    static func picks(for posts: [ContractPost]) -> [String: Pick] {
        var result: [String: Pick] = [:]
        for post in posts { if let pick = pick(post) { result[post.id] = pick } }

        // An author's unmatched saves follow their others, if most share a topic.
        var byAuthor: [String: [String: Int]] = [:]
        for post in posts {
            guard let pick = result[post.id], pick.signal != .collection else { continue }
            byAuthor[post.author.username.lowercased(), default: [:]][pick.slug, default: 0] += 1
        }
        for post in posts where result[post.id] == nil {
            guard let counts = byAuthor[post.author.username.lowercased()] else { continue }
            let total = counts.values.reduce(0, +)
            // Ties broken by slug: `Dictionary.max` alone is random on ties (LESSONS.md).
            guard let top = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }),
                  top.value >= 2, top.value * 2 > total, let topic = topic(forSlug: top.key) else { continue }
            result[post.id] = Pick(slug: topic.id, label: topic.label, signal: .author)
        }

        for post in posts where result[post.id] == nil {
            if let topic = platformTopic(post) { result[post.id] = Pick(slug: topic.id, label: topic.label, signal: .platform) }
        }
        return result
    }

    /// One post's own signals: its collection, else its best-scoring lexicon topic.
    static func pick(_ post: ContractPost) -> Pick? {
        if let name = post.collections.lazy.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty && !genericCollections.contains(TextMatch.fold($0)) }) {
            return Pick(slug: SortRules.slug(name), label: name, signal: .collection)
        }
        guard let best = scores(post).first, best.score >= minimumScore else { return nil }
        return Pick(slug: best.topic.id, label: best.topic.label, signal: best.signal)
    }

    static let minimumScore = 2
    private static let hashtagWeight = 3, captionWeight = 2, weakWeight = 1, usernameWeight = 1
    /// Default folders some sources report as collections; they say nothing.
    static let genericCollections: Set<String> = ["saved", "all posts", "all", "saved posts"]

    /// Lexicon topics that match, best first. Each word or tag counts once, at its
    /// strongest source. Ties go to the earlier (more specific) topic.
    static func scores(_ post: ContractPost) -> [(topic: Topic, score: Int, signal: Signal)] {
        let text = Text(post)
        var result: [(topic: Topic, score: Int, signal: Signal, index: Int)] = []
        for (index, topic) in lexicon.enumerated() {
            var score = 0, usernameHit = false
            var signal = Signal.author
            for entry in compiledWords[index] {
                if text.tags.contains(where: entry.matches) {
                    score += hashtagWeight; signal = min(signal, .hashtag)
                } else if text.has(entry) {
                    score += entry.weak ? weakWeight : captionWeight; signal = min(signal, .caption)
                } else if !entry.weak, text.usernameParts.contains(where: entry.matches) {
                    usernameHit = true
                }
            }
            for stem in topic.tags {
                if text.tags.contains(where: { matchesTag(stem, $0) }) {
                    score += hashtagWeight; signal = min(signal, .hashtag)
                } else if matchesTag(stem, text.username) {
                    usernameHit = true
                }
            }
            // The author's name ("vince.quant") counts once: it backs a match up, never makes one.
            if usernameHit, score > 0 { score += usernameWeight }
            if score > 0 { result.append((topic, score, signal, index)) }
        }
        return result.sorted { ($1.score, $0.index) < ($0.score, $1.index) }.map { ($0.topic, $0.score, $0.signal) }
    }

    // MARK: - Names

    /// The lexicon (or platform) topic behind a slug.
    static func topic(forSlug slug: String) -> Topic? {
        topicsByID[slug]
    }

    /// Label + emoji for a slug the fallback made, when no model names it: the
    /// lexicon's, or the collection's own name.
    static func name(forSlug slug: String, collections: [String]) -> (label: String, emoji: String)? {
        if let topic = topic(forSlug: slug) { return (topic.label, topic.emoji) }
        if let collection = collections.first(where: { SortRules.slug($0) == slug }) { return (collection, "📁") }
        return nil
    }

    /// SF Symbol for a topic named like a lexicon topic (the simulator can't draw emoji).
    static func symbol(forLabel label: String) -> String? {
        symbolsByLabel[TextMatch.fold(label)]
    }

    private static let topicsByID = Dictionary((lexicon + platformTopics).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    private static let symbolsByLabel = Dictionary((lexicon + platformTopics).map { (TextMatch.fold($0.label), $0.symbol) },
                                                   uniquingKeysWith: { a, _ in a })

    // MARK: - Platform, the last resort

    static let platformTopics: [Topic] = [
        Topic(id: "notes", label: "Notes", symbol: "note.text", emoji: "📝", words: []),
        Topic(id: "links", label: "Links", symbol: "link", emoji: "🔗", words: []),
        Topic(id: "posts-from-x", label: "Posts from X", symbol: "text.bubble.fill", emoji: "🐦", words: []),
        Topic(id: "posts-from-tiktok", label: "Posts from TikTok", symbol: "music.note.tv", emoji: "🎵", words: []),
        Topic(id: "posts-from-facebook", label: "Posts from Facebook", symbol: "person.2.fill", emoji: "👥", words: []),
    ]

    /// Instagram has no platform topic: an unmatched reel is just "Other".
    private static func platformTopic(_ post: ContractPost) -> Topic? {
        let id: String? = switch (post.platform, post.kind) {
        case (_, .note), (.whatsapp, _): "notes"
        case (_, .link), (.web, _): "links"
        case (.x, _): "posts-from-x"
        case (.tiktok, _): "posts-from-tiktok"
        case (.facebook, _): "posts-from-facebook"
        case (.instagram, _): nil
        }
        return id.flatMap(topic(forSlug:))
    }

    // MARK: - Tokens

    /// A post's text, folded (case, diacritics) and split into tokens.
    struct Text {
        var caption: String
        var tokens: Set<String>
        /// " a b c ": for phrase entries.
        var joined: String
        var tags: [String]
        var username: String
        var usernameParts: [String]

        init(_ post: ContractPost) {
            caption = post.caption ?? ""
            let words = TopicFallback.words(caption)
            tokens = Set(words.flatMap(TopicFallback.variants))
            joined = " " + words.joined(separator: " ") + " "
            var tags = post.hashtags.map(TextMatch.fold)
            if tags.isEmpty { tags = SavedPost.hashtags(in: post.caption).map(TextMatch.fold) }
            self.tags = tags
            username = TextMatch.fold(post.author.username)
            usernameParts = username.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }

        func has(_ entry: Entry) -> Bool {
            switch entry.kind {
            case .exact: entry.forms.contains(where: tokens.contains)
            case .prefix: tokens.contains { $0.hasPrefix(entry.text) }
            case .phrase: joined.contains(entry.text)
            case .symbol: caption.contains(entry.text)
            }
        }
    }

    /// A lexicon word, parsed once (scoring every save is on the sort's critical path).
    struct Entry: Sendable {
        enum Kind: Sendable { case exact, prefix, phrase, symbol }
        var kind: Kind
        /// The prefix stem, " the phrase ", or the symbol.
        var text: String
        /// Whole-token forms: the word + -s/-es, or the phrase run together (as a hashtag).
        var forms: [String]
        var weak: Bool

        init(_ raw: String) {
            weak = raw.hasPrefix("~")
            let word = weak ? String(raw.dropFirst()) : raw
            if word.contains(" ") {
                kind = .phrase; text = " \(word) "; forms = [word.replacingOccurrences(of: " ", with: "")]
            } else if !word.contains(where: \.isLetter) {
                kind = .symbol; text = word; forms = [word]
            } else if word.hasSuffix("*") {
                kind = .prefix; text = String(word.dropLast()); forms = []
            } else {
                kind = .exact; text = word; forms = [word, word + "s", word + "es"]
            }
        }

        /// Against one whole token: a hashtag or a username part.
        func matches(_ token: String) -> Bool {
            kind == .prefix ? token.hasPrefix(text) : forms.contains(token)
        }
    }

    private static let compiledWords: [[Entry]] = lexicon.map { $0.words.map(Entry.init) }

    /// Caption words without #tags and @handles, folded: "Best #nyc pizza @joes" → ["best", "pizza"].
    static func words(_ text: String) -> [String] {
        let bare = text.replacing(/[#@][\p{L}\p{N}_.]+/, with: " ")
        return TextMatch.fold(bare).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// A token and, for Hebrew, the token without its one-letter prefixes
    /// ("במיקס" → "מיקס", "והטבעונות" → "טבעונות").
    static func variants(_ token: String) -> [String] {
        guard let first = token.unicodeScalars.first, (0x05D0...0x05EA).contains(first.value) else { return [token] }
        var out = [token]
        var rest = Substring(token)
        // Two letters only after "ו"/"ש" ("והטבעונות"); "למספר" must not become "ספר".
        for i in 0..<2 {
            guard let c = rest.first, hebrewPrefixes.contains(c), rest.count >= 4 else { break }
            if i == 1, let lead = token.first, lead != "ו", lead != "ש" { break }
            rest = rest.dropFirst()
            out.append(String(rest))
        }
        return out
    }

    private static let hebrewPrefixes: Set<Character> = ["ה", "ו", "ב", "ל", "מ", "ש", "כ"]

    /// A hashtag stem against a hashtag (or a username).
    static func matchesTag(_ stem: String, _ tag: String) -> Bool {
        if tag == stem { return true }
        if stem.count >= 4, tag.hasPrefix(stem) || tag.hasSuffix(stem) { return true }
        return stem.count >= 5 && tag.contains(stem)
    }

    // MARK: - The lexicon

    /// Broad everyday topics, most specific first (ties go to the earlier one).
    /// Words are folded (lowercase, no accents); English, Hebrew, and basic
    /// Spanish/Portuguese for food, travel and fitness. Grow it from the coverage
    /// test's list of unmatched hashtags.
    static let lexicon: [Topic] = [
        Topic(id: "music-production", label: "Music production", symbol: "slider.vertical.3", emoji: "🎛️",
              words: ["producer", "~production", "plugin*", "vst*", "daw", "mixing", "mastering", "mixdown", "eq", "compressor",
                      "compression", "sidechain", "synth*", "serum", "preset*", "sample pack", "~samples", "drum kit", "808", "808s",
                      "flstudio", "ableton", "logic pro", "fl studio", "beatmaker", "beatmaking", "make beats", "vocal chain",
                      "sound design", "reverb", "saturation", "midi", "~arrangement", "~melody", "~chord", "~loops",
                      "מיקס", "מיקסים", "מאסטרינג", "קומפרס*", "פלאגין*", "ווקאל*", "סאונד", "ביט", "ביטים", "הפקה", "מפיק*", "מולטי"],
              tags: ["producer", "production", "flstudio", "ableton", "logicpro", "beatmak", "beats", "mixing", "mastering",
                     "sounddesign", "serum", "presets", "omnisphere", "spectrasonics", "arturia", "vstplugin", "plugin", "audioeng",
                     "studiolife", "homestudio", "samplepack", "drumkit", "synth", "flp", "behindthebeat", "beatbreakdown", "musictheory",
                     "sampling", "productor"]),
        Topic(id: "guitar-instruments", label: "Guitar & instruments", symbol: "guitars.fill", emoji: "🎸",
              words: ["guitar*", "guitarra", "guitare", "piano", "pianist", "bass guitar", "ukulele", "drums", "drummer", "violin",
                      "~riff", "~tabs", "fretboard", "pentatonic", "~scale", "strumming", "fingerstyle", "~solo",
                      "גיטרה", "פסנתר", "תופים"],
              tags: ["guitar", "guitarra", "piano", "ukulele", "drummer", "violin", "fingerstyle", "chordprogression", "acoustic"]),
        Topic(id: "coffee", label: "Coffee", symbol: "cup.and.saucer.fill", emoji: "☕",
              words: ["coffee", "espresso", "latte", "lattes", "cappuccino", "matcha", "barista", "pour over", "cold brew",
                      "קפה", "אספרסו", "cafe con leche", "cafezinho"],
              tags: ["coffee", "espresso", "latte", "barista", "matcha", "cafe"]),
        Topic(id: "restaurants-cafes", label: "Restaurants & cafés", symbol: "fork.knife.circle.fill", emoji: "🍽️",
              words: ["restaurant*", "brunch", "~rooftop", "bakery", "bakeries", "pizzeria", "bistro", "eatery", "omakase",
                      "speakeasy", "food spot", "food spots", "~must try", "where to eat", "best pizza", "best burger",
                      "מסעדה", "מסעדות", "מסעדת", "restaurante", "restaurantes"],
              tags: ["nycfood", "foodie", "restaurant", "brunch", "eats", "foodspot", "foodguide", "foodblogger", "foodreview"]),
        Topic(id: "food-recipes", label: "Food & recipes", symbol: "fork.knife", emoji: "🍳",
              words: ["recipe*", "ingredient*", "~cook*", "bake", "baked", "baking", "tofu", "~pasta", "pancake*", "~breakfast", "~dinner",
                      "~lunch", "~meal*", "dessert*", "cookie*", "~cake", "salad", "soup", "~sauce", "~chicken", "protein pancakes",
                      "oats", "tortilla*", "vegan", "plant based", "air fryer", "~delicious", "~tasty",
                      "מתכון*", "מתכונ*", "מרכיבים", "~ארוחת", "ארוחה", "אורז", "עוף", "פרגיות", "עוגה", "עוגיות", "בישול", "מה צריך",
                      "receita*", "receta*", "comida", "cocina", "cozinha", "فطور", "وصفات"],
              tags: ["recipe", "food", "cooking", "vegan", "plantbased", "healthyrecipe", "baking", "מתכון", "טבעונ", "צמחונ"]),
        Topic(id: "coding", label: "Coding", symbol: "chevron.left.forwardslash.chevron.right", emoji: "💻",
              words: ["code", "coding", "coder", "programming", "programmer", "python", "javascript", "typescript",
                      "~react", "github", "repo", "leetcode", "algorithm*", "~api", "frontend", "backend", "~database",
                      "sql", "numpy", "~website", "html", "css", "~software", "~engineer", "~engineering", "vibecoding",
                      "vibe coding", "claude code", "~cursor", "hackathon", "computer science", "~terminal", "open source",
                      "קוד", "תכנות", "מתכנת*", "~אתר", "~אתרים"],
              tags: ["coding", "programming", "developer", "softwareeng", "computerscience", "vibecod", "webdev", "python",
                     "javascript", "leetcode", "codinglife", "websitebuilding", "github", "100daysofcode"]),
        Topic(id: "tech-ai", label: "Tech & AI", symbol: "cpu", emoji: "🤖",
              words: ["ai", "chatgpt", "gpt", "claude", "openai", "anthropic", "gemini", "llm", "llms", "~agent", "prompt*",
                      "automation*", "~robot*", "tech", "technology", "~iphone", "~apple", "~app", "~gadget*", "nvidia", "~model",
                      "deepmind", "artificial intelligence", "machine learning", "~tools", "chatbot",
                      "בינה מלאכותית", "טכנולוגיה", "אפליקציה", "אפליקציות"],
              tags: ["aitools", "aitips", "artificialintelligence", "chatgpt", "claude", "openai", "machinelearning", "techtips",
                     "technology", "techreels", "tech", "ainews", "gadget", "automation"]),
        Topic(id: "design", label: "Design", symbol: "paintpalette.fill", emoji: "🎨",
              words: ["~design", "designer*", "font", "fonts", "typography", "typeface", "figma", "photoshop", "illustrator",
                      "~logo", "~branding", "ui", "ux", "color palette", "~colour", "mockup", "canva", "~graphic",
                      "עיצוב", "מעצב*", "פונט*"],
              tags: ["design", "typography", "photoshop", "illustrator", "figma", "uidesign", "uxdesign", "webdesign", "branding",
                     "logo", "graphicdesign", "fonts"]),
        Topic(id: "finance-investing", label: "Finance & investing", symbol: "chart.line.uptrend.xyaxis", emoji: "📈",
              words: ["finance", "financial", "invest*", "stock", "stocks", "trading", "trader*", "quant", "quants", "hedge fund*",
                      "~portfolio", "~options", "~market", "~markets", "crypto", "bitcoin", "etf", "etfs", "dividend*", "wall street",
                      "hft", "backtest*", "volatility", "~money", "~wealth", "~budget*", "tradingview", "polymarket", "citadel",
                      "כסף", "השקעה", "השקעות", "מניות", "מניה", "בורסה", "ריבית", "פיננסי*"],
              tags: ["finance", "invest", "stocks", "trading", "quant", "crypto", "wallstreet", "money", "personalfinance",
                     "daytrad", "forex", "investmentbanking"]),
        Topic(id: "career", label: "Career", symbol: "briefcase.fill", emoji: "💼",
              words: ["career*", "resume", "cv", "interview*", "recruiter*", "~job", "~jobs", "linkedin", "salary", "internship*",
                      "hiring", "~promotion", "negotiat*", "cold email", "~networking", "~boss", "~coworker*", "~office",
                      "קריירה", "ראיון", "משרה", "קורות חיים", "~עבודה"],
              tags: ["career", "jobsearch", "resume", "interview", "internship", "linkedin", "jobtips", "careeradvice"]),
        Topic(id: "creator-business", label: "Creator & business", symbol: "megaphone.fill", emoji: "📣",
              words: ["~views", "~viral", "~followers", "~hook", "content creator*", "~creator*", "youtube*", "seo", "marketing",
                      "~brand", "~business*", "entrepreneur*", "startup*", "side hustle", "clipping", "ecommerce", "~sales",
                      "~customers", "founder*", "שיווק", "עסק", "עסקים", "יזמ*"],
              tags: ["marketing", "entrepreneur", "sidehustle", "smallbusiness", "contentcreat", "socialmedia", "growth",
                     "onlinebusiness", "ecommerce", "startup", "branding", "youtubeautomation", "onlinemoney", "howtogrow"]),
        Topic(id: "languages", label: "Languages", symbol: "character.bubble.fill", emoji: "🗣️",
              words: ["pronunciation", "pronounce*", "vocabulary", "grammar", "fluent*", "~accent", "~slang", "learn english",
                      "learn spanish", "~spanish", "~portuguese", "~russian", "~french", "~arabic", "~italian", "~japanese", "~german",
                      "אנגלית", "ערבית", "מבטא", "~מילים", "~דיבור", "רוסית", "ספרדית", "צרפתית"],
              tags: ["learnenglish", "english", "learnportuguese", "learnspanish", "russian", "language", "אנגלית", "ערבית",
                     "דיבורשוטף", "מבטא", "polyglot"]),
        Topic(id: "study-learning", label: "Study & learning", symbol: "graduationcap.fill", emoji: "🎓",
              words: ["study", "studying", "~student*", "~college", "~university", "~lecture*", "~course*", "~learn", "~learning",
                      "~math", "calculus", "~statistics", "~notes", "homework", "harvard", "mit", "stanford",
                      "לימודים", "~אוניברסיט*", "סטודנט*", "מבחן", "מבחנים", "~קורס"],
              tags: ["study", "student", "college", "university", "studytips", "learnoninstagram", "education", "math"]),
        Topic(id: "books", label: "Books", symbol: "book.fill", emoji: "📚",
              words: ["~book", "~books", "novel*", "~reading", "~author", "kindle", "audiobook*", "~ספר", "~ספרים", "~קריאה"],
              tags: ["books", "booktok", "bookstagram", "reading", "booklover"]),
        Topic(id: "movies-tv", label: "Movies & TV", symbol: "tv.fill", emoji: "🎬",
              words: ["movie*", "film", "cinema", "netflix", "~series", "~episode*", "~season", "anime", "~actor", "~actress",
                      "hbo", "~trailer", "oscar*", "documentary", "cartoon*", "spongebob", "simpsons",
                      "~סרט", "סרטים", "~סדרה", "סדרות", "~פרק", "אנימה", "נטפליקס"],
              tags: ["movie", "film", "netflix", "cinema", "anime", "tvshow", "cartoon", "spongebob", "nickelodeon"]),
        Topic(id: "music", label: "Music", symbol: "music.note", emoji: "🎵",
              words: ["song*", "album*", "out now", "~music", "rapper*", "rap", "~singer", "concert*", "lyrics", "~track", "~tracks",
                      "~single", "~verse", "remix*", "~playlist*", "~listen", "spotify", "soundcloud", "hip hop", "hiphop", "drake",
                      "kanye", "~travis", "uzi", "carti", "yeat", "~dj", "~festival", "~tour", "~artist", "vinyl", "studio session",
                      "~שיר", "שירים", "אלבום", "זמר*", "ראפ", "הופעה", "מוזיקה", "musica", "música"],
              tags: ["music", "rap", "hiphop", "newmusic", "song", "concert", "singer", "musician", "rnb", "spotify", "drill",
                     "techno", "housemusic", "ukg", "lyrics", "soundcloud", "freestyle"]),
        Topic(id: "dance", label: "Dance", symbol: "figure.dance", emoji: "💃",
              words: ["dance", "dancing", "dancer", "choreo*", "~footwork", "salsa", "bachata", "ריקוד", "ריקודים"],
              tags: ["dance", "cwalk", "choreograph", "dancetutorial", "footwork", "salsa", "bachata"]),
        Topic(id: "fitness-workouts", label: "Fitness & workouts", symbol: "figure.strengthtraining.traditional", emoji: "💪",
              words: ["workout*", "exercise*", "gym", "~reps", "~sets", "squat*", "deadlift*", "pushup*", "push up", "pullup*",
                      "~abs", "~core", "~muscle*", "bicep*", "tricep*", "glute*", "calisthenics", "hiit", "cardio", "~running",
                      "boxing", "~stretch*", "mobility", "~posture", "back pain", "plank", "~strength", "handstand", "yoga", "pilates",
                      "אימון*", "כושר", "שריר*", "חזרות", "מתיחות", "treino", "entrenamiento", "ejercicio*", "exercicio*"],
              tags: ["fitness", "workout", "gym", "calisthenics", "mobility", "stretch", "yoga", "pilates", "bodybuilding",
                     "backpain", "boxing", "running", "training", "fitfam", "absworkout", "fighttips"]),
        // Mental health before the body-side "Health & wellness": a different job (Keep close, TopicJobs).
        Topic(id: "mental-health", label: "Mental health", symbol: "brain.head.profile", emoji: "🫶",
              words: ["mental health", "therapy", "therapist", "anxiety", "anxious", "burnout", "burned out", "mindfulness",
                      "mindful", "meditation", "meditate", "self care", "selfcare", "healing", "journaling", "breathwork",
                      "~overthinking", "~trauma", "inner child", "nervous system", "~panic", "~grief",
                      "בריאות הנפש", "בריאות נפשית", "טיפול רגשי", "פסיכולוג*", "חרדה", "חרדות", "שחיקה", "מיינדפולנס",
                      "מדיטציה", "ריפוי", "נשימות", "~דיכאון"],
              tags: ["mentalhealth", "therapy", "anxiety", "burnout", "mindfulness", "meditation", "selfcare", "healing",
                     "journaling", "breathwork", "selflove", "mentalhealthawareness", "בריאותהנפש"]),
        Topic(id: "health-wellness", label: "Health & wellness", symbol: "heart.fill", emoji: "🧘",
              words: ["~health", "~healthy", "~sleep", "~stress", "melatonin", "supplement*", "vitamin*", "~doctor", "~dr",
                      "migraine*", "headache*", "~gut", "~brain", "dopamine",
                      "caffeine", "~hormone*", "~skin", "nutrition", "~diet", "weight loss", "~calories", "~symptom*", "inflammation",
                      "בריאות", "~שינה", "תוספ*", "~רופא", "כאב*", "~המוח", "~מוח", "תזונה", "דיאטה", "קפאין"],
              tags: ["health", "wellness", "nutrition", "sleep", "healthy", "biohack", "בריאות"]),
        Topic(id: "animals-pets", label: "Animals & pets", symbol: "pawprint.fill", emoji: "🐾",
              words: ["dog", "puppy", "~cat", "kitten*", "~pet", "animal*", "cow", "calf", "wildlife", "~bird*", "~horse*",
                      "חיות", "כלב*", "חתול*", "פרה", "פרות", "עגל*", "בעלי חיים", "בעלחיים"],
              tags: ["dog", "cat", "puppy", "kitten", "pets", "animal", "wildlife", "cow", "חיות", "בעליחיים", "אנימלס", "פרה",
                     "עגל"]),
        Topic(id: "travel", label: "Travel", symbol: "airplane", emoji: "✈️",
              words: ["travel*", "~trip", "~flight*", "~hotel*", "airport", "~beach*", "~island*", "~vacation", "itinerary",
                      "day trip", "things to do", "hidden gem*", "~visit", "~destination*", "passport", "airbnb", "~hike", "~hiking",
                      "טיול*", "טיסה", "טיסות", "חופשה", "מלון", "~חוף", "חופים", "לטייל", "מעיין",
                      "viagem", "viaje", "viajar", "praia", "playa"],
              tags: ["travel", "visit", "wanderlust", "bucketlist", "explorenyc", "thingstodo", "vacation", "trip", "hiking",
                     "beach", "טיול"]),
        Topic(id: "fashion-style", label: "Fashion & style", symbol: "tshirt.fill", emoji: "👗",
              words: ["outfit*", "fashion", "~style", "~styling", "~wear", "~shirt*", "sneaker*", "~shoe*", "~dress", "~jeans", "~jacket",
                      "streetwear", "ootd", "אופנה", "בגדים", "סטייל"],
              tags: ["fashion", "outfit", "ootd", "streetwear", "sneaker", "menswear"]),
        Topic(id: "beauty", label: "Beauty", symbol: "wand.and.stars", emoji: "💄",
              words: ["makeup", "skincare", "~hair", "hairstyle*", "~nails", "lipstick", "mascara", "serum skin", "איפור", "~שיער"],
              tags: ["makeup", "skincare", "beauty", "hair", "nails"]),
        Topic(id: "tattoos", label: "Tattoos", symbol: "paintbrush.pointed.fill", emoji: "🖋️",
              words: ["tattoo*", "~flash", "~ink", "~placement", "~healed", "~session", "קעקוע*"],
              tags: ["tattoo", "ink", "flashtattoo"]),
        Topic(id: "home-interior", label: "Home & interior", symbol: "sofa.fill", emoji: "🛋️",
              words: ["interior*", "~apartment", "~decor", "furniture", "living room", "~bedroom", "~kitchen", "renovation", "cleaning",
                      "~organiz*", "~plants", "~דירה", "ריהוט", "ניקיון"],
              tags: ["interior", "homedecor", "decor", "apartment", "cleaning", "organiz", "homedesign"]),
        Topic(id: "art-photography", label: "Art & photography", symbol: "camera.fill", emoji: "📷",
              words: ["~art", "~artist*", "~painting*", "~drawing*", "~sketch*", "~photo", "photography", "photographer",
                      "~camera", "~lens", "film look", "cinematic", "color grade", "videography", "museum", "~gallery", "sculpture",
                      "~צילום", "ציור", "אמנות"],
              tags: ["art", "photography", "painting", "drawing", "artist", "cinematography", "filmmaker", "videography",
                     "iphonephotography", "illustration"]),
        Topic(id: "humor-memes", label: "Humor & memes", symbol: "face.smiling.inverse", emoji: "😂",
              words: ["meme*", "lol", "lmao", "lmfao", "pov", "funny", "joke*", "comedy", "skit", "prank*", "~bro", "~nah",
                      "😂", "🤣", "💀", "😭", "חחח*", "מצחיק*", "צחוק"],
              tags: ["meme", "funny", "comedy", "humor", "lol", "skit", "pov", "prank", "jokes"]),
        Topic(id: "sports", label: "Sports", symbol: "sportscourt.fill", emoji: "⚽",
              words: ["football", "soccer", "basketball", "nba", "nfl", "messi", "ronaldo", "lebron", "~tennis", "~goal", "~league",
                      "ufc", "~fight", "כדורגל", "כדורסל", "futbol", "futebol"],
              tags: ["football", "soccer", "nba", "nfl", "basketball", "ufc", "sports", "tennis"]),
        Topic(id: "cars", label: "Cars", symbol: "car.fill", emoji: "🚗",
              words: ["~car", "~engine", "~driving", "tesla", "bmw", "porsche", "ferrari", "used car", "~רכב", "~אוטו", "מכונית"],
              tags: ["car", "cartok", "automobile", "supercar", "jdm"]),
        Topic(id: "parenting-family", label: "Parenting & family", symbol: "figure.and.child.holdinghands", emoji: "👶",
              words: ["~baby", "toddler*", "~parent*", "~kids", "~child", "~children", "~mom", "~dad", "pregnan*", "newborn",
                      "~ילדים", "~ילד", "תינוק*", "הורים", "~אמא", "~אבא"],
              tags: ["parenting", "momlife", "dadlife", "toddler", "kids"]),
        Topic(id: "relationships", label: "Relationships", symbol: "heart.circle.fill", emoji: "❤️",
              words: ["relationship*", "dating", "date night", "girlfriend", "boyfriend", "~marriage", "~married", "~couple*",
                      "~partner", "~love", "זוגיות", "דייט*", "~אהבה"],
              tags: ["relationship", "dating", "couple", "love", "marriage"]),
        Topic(id: "productivity", label: "Productivity", symbol: "checklist", emoji: "✅",
              words: ["productivity", "productive", "~habit*", "~routine", "~focus", "notion", "excel", "spreadsheet*", "powerpoint",
                      "~shortcut*", "~hack", "life hack", "time management", "~discipline", "motivation*", "mindset",
                      "פרודוקטיב*", "הרגל*"],
              tags: ["productivity", "lifehack", "excel", "powerpoint", "notion", "motivation", "mindset", "selfimprovement",
                     "discipline"]),
        Topic(id: "shopping-deals", label: "Shopping & deals", symbol: "bag.fill", emoji: "🛍️",
              words: ["~sale", "discount*", "~deal", "coupon*", "promo code", "amazon", "~shop", "~shopping", "~buy",
                      "on sale", "מבצע", "הנחה", "קופון"],
              tags: ["sale", "deals", "shopping", "amazonfinds", "ad", "sponsored", "partner"]),
        Topic(id: "news-politics", label: "News & politics", symbol: "newspaper.fill", emoji: "📰",
              words: ["news", "~breaking", "election*", "~president", "trump", "biden", "government", "politic*", "~war", "~minister",
                      "congress", "senate", "protest*", "~israel", "~gaza", "~iran", "~ukraine", "~court", "~law", "~cia",
                      "פוליטיקה", "בחירות", "ממשלה", "השר", "~שר", "מלחמה", "חטופ*", "כנסת", "הפגנה", "נתניהו", "ביבי",
                      "ראש הממשלה", "~מדינה", "~המדינה", "~צבא", "~חייל*"],
              tags: ["news", "politics", "israel", "gaza", "election", "breakingnews", "פוליטיקה", "חדשות"]),
        Topic(id: "faith", label: "Faith & spirituality", symbol: "sparkles", emoji: "🙏",
              words: ["torah", "shabbat", "shabbos", "rabbi", "bible", "jesus", "christ", "quran", "prayer", "pray", "church",
                      "mosque", "~god", "~faith", "spiritual*", "תורה", "שבת", "הרב", "תפילה", "אמונה", "גאולה"],
              tags: ["faith", "jesus", "torah", "bible", "islam", "muslim", "quran", "christian", "prayer", "תורה"]),
        Topic(id: "science", label: "Science", symbol: "atom", emoji: "🔬",
              words: ["science", "scientist*", "physics", "chemistry", "biology", "~space", "nasa", "~universe", "~research*",
                      "~experiment*", "quantum", "~planet*", "מדע", "פיזיקה"],
              tags: ["science", "physics", "space", "nasa", "astronomy", "biology", "chemistry"]),
        Topic(id: "gaming", label: "Gaming", symbol: "gamecontroller.fill", emoji: "🎮",
              words: ["~game", "~games", "gaming", "video game", "video games", "gamer",
                      "playstation", "xbox", "nintendo", "minecraft", "fortnite", "chess",
                      "שחמט", "גיימינג"],
              tags: ["gaming", "gamer", "videogames", "playstation", "xbox", "nintendo", "chess", "שחמט"]),
        Topic(id: "diy-crafts", label: "DIY & crafts", symbol: "hammer.fill", emoji: "🔨",
              words: ["diy", "craft*", "handmade", "woodwork*", "sewing", "knit*", "crochet", "3d print*", "build your own"],
              tags: ["diy", "crafts", "handmade", "woodworking", "crochet", "sewing"]),
        Topic(id: "events-nightlife", label: "Events & nightlife", symbol: "party.popper.fill", emoji: "🎉",
              words: ["~party", "~parties", "nightlife", "~club", "~clubs", "rave", "~event*", "~tickets", "~bar", "~bars", "cocktail*",
                      "מסיבה", "מסיבות", "~אירוע*"],
              tags: ["nightlife", "party", "rave", "clubbing", "cocktail", "events"]),
    ]
}
