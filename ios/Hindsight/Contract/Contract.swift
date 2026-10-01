import Foundation

/// The data-contract file (docs/data-contract.md, v1): everything the pipeline
/// produces for one user. Decoded with `.convertFromSnakeCase`; unknown keys are ignored.
struct ContractFile: Codable, Sendable {
    var contractVersion: Int
    var generatedAt: String?
    var user: ContractUser
    var posts: [ContractPost]
    var topics: [ContractTopic]
    var items: [ContractItem]

    static let supportedVersion = 1

    static func decode(_ data: Data) throws -> ContractFile {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ContractFile.self, from: data)
    }
}

struct ContractUser: Codable, Sendable, Hashable {
    var handle: String
    var platforms: [String]
}

/// Where a topic or item lives. `none` topics decode to `nil` (Everything else).
enum LegoScreen: String, Codable, Sendable, CaseIterable, Identifiable {
    case map, fitness, learn

    var id: String { rawValue }

    var defaultTitle: String {
        switch self {
        case .map: "Map"
        case .fitness: "Fitness"
        case .learn: "Learn"
        }
    }

    var defaultEmoji: String {
        switch self {
        case .map: "🗺️"
        case .fitness: "💪"
        case .learn: "📚"
        }
    }

    /// SF Symbol for tab bars (the simulator can't render emoji; see LESSONS).
    var symbol: String {
        switch self {
        case .map: "map.fill"
        case .fitness: "figure.flexibility"
        case .learn: "books.vertical.fill"
        }
    }
}

enum Confidence: String, Codable, Sendable {
    case high, low

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Confidence(rawValue: raw) ?? .low
    }
}

// MARK: - posts[]

struct ContractPost: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var platform: Platform
    var url: URL
    var kind: SavedPost.Kind
    var author: Author
    var caption: String?
    var hashtags: [String]
    var mentions: [Mention]
    var collections: [String]
    var savedAt: String?
    var postedAt: String?
    var thumbnailUrl: URL?
    var locationTag: LocationTag?
    var language: String?

    struct Author: Codable, Sendable, Hashable {
        var username: String
        var displayName: String?
    }

    struct Mention: Codable, Sendable, Hashable {
        var username: String
        var displayName: String?
    }

    struct LocationTag: Codable, Sendable, Hashable {
        var name: String?
        var address: String?
        var lat: Double?
        var lng: Double?
    }

    enum CodingKeys: String, CodingKey {
        case id, platform, url, kind, author, caption, hashtags, mentions, collections
        case savedAt, postedAt, thumbnailUrl, locationTag, language
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        platform = (try? c.decode(Platform.self, forKey: .platform)) ?? .instagram
        url = try c.decode(URL.self, forKey: .url)
        kind = SavedPost.Kind(label: (try? c.decode(String.self, forKey: .kind)) ?? "unknown")
        author = try c.decode(Author.self, forKey: .author)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        hashtags = try c.decodeIfPresent([String].self, forKey: .hashtags) ?? []
        mentions = try c.decodeIfPresent([Mention].self, forKey: .mentions) ?? []
        collections = try c.decodeIfPresent([String].self, forKey: .collections) ?? []
        savedAt = try c.decodeIfPresent(String.self, forKey: .savedAt)
        postedAt = try c.decodeIfPresent(String.self, forKey: .postedAt)
        thumbnailUrl = try? c.decodeIfPresent(URL.self, forKey: .thumbnailUrl)
        locationTag = try? c.decodeIfPresent(LocationTag.self, forKey: .locationTag)
        language = try c.decodeIfPresent(String.self, forKey: .language)
    }

    init(id: String, platform: Platform = .instagram, url: URL, kind: SavedPost.Kind = .reel,
         author: String, caption: String?, hashtags: [String] = [], mentions: [Mention] = [],
         collections: [String] = [], savedAt: String? = nil) {
        self.id = id
        self.platform = platform
        self.url = url
        self.kind = kind
        self.author = Author(username: author, displayName: nil)
        self.caption = caption
        self.hashtags = hashtags
        self.mentions = mentions
        self.collections = collections
        self.savedAt = savedAt
    }

    /// When the user saved it. Date-only strings are local midnight (see LESSONS).
    var savedDate: Date? { savedAt.flatMap(ContractDate.parse) }

    /// "@author" for bylines.
    var byline: String { "@\(author.username)" }

    /// First non-empty caption line, for list rows.
    var firstLine: String? {
        caption?.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }
}

enum ContractDate {
    static func parse(_ string: String) -> Date? {
        if string.count == 10 {
            let parts = string.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        return try? Date(string, strategy: .iso8601)
    }
}

// MARK: - topics[]

struct ContractTopic: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var label: String
    var emoji: String?
    /// `nil` = `none` (Everything else).
    var legoScreen: LegoScreen?
    var confidence: Confidence
    var postIds: [String]
    var samplePostIds: [String]
    var sourceCollections: [String]
    var ambiguity: Ambiguity?

    struct Ambiguity: Codable, Sendable, Hashable {
        var question: String
        var options: [Option]

        struct Option: Codable, Sendable, Hashable {
            var label: String
            /// `nil` = leave it out.
            var legoScreen: LegoScreen?

            init(label: String, legoScreen: LegoScreen?) {
                self.label = label
                self.legoScreen = legoScreen
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                label = try c.decode(String.self, forKey: .label)
                legoScreen = (try? c.decodeIfPresent(String.self, forKey: .legoScreen)).flatMap { $0.flatMap(LegoScreen.init(rawValue:)) }
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, label, emoji, legoScreen, confidence, postIds, samplePostIds, sourceCollections, ambiguity
    }

    init(id: String, label: String, emoji: String? = nil, legoScreen: LegoScreen?, confidence: Confidence = .high,
         postIds: [String], samplePostIds: [String]? = nil, sourceCollections: [String] = [], ambiguity: Ambiguity? = nil) {
        self.id = id
        self.label = label
        self.emoji = emoji
        self.legoScreen = legoScreen
        self.confidence = confidence
        self.postIds = postIds
        self.samplePostIds = samplePostIds ?? Array(postIds.prefix(3))
        self.sourceCollections = sourceCollections
        self.ambiguity = ambiguity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        legoScreen = LegoScreen(rawValue: try c.decode(String.self, forKey: .legoScreen))
        confidence = (try? c.decode(Confidence.self, forKey: .confidence)) ?? .high
        postIds = try c.decodeIfPresent([String].self, forKey: .postIds) ?? []
        samplePostIds = try c.decodeIfPresent([String].self, forKey: .samplePostIds) ?? []
        sourceCollections = try c.decodeIfPresent([String].self, forKey: .sourceCollections) ?? []
        ambiguity = try c.decodeIfPresent(Ambiguity.self, forKey: .ambiguity)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(emoji, forKey: .emoji)
        try c.encode(legoScreen?.rawValue ?? "none", forKey: .legoScreen)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(postIds, forKey: .postIds)
        try c.encode(samplePostIds, forKey: .samplePostIds)
        try c.encode(sourceCollections, forKey: .sourceCollections)
        try c.encodeIfPresent(ambiguity, forKey: .ambiguity)
    }
}

// MARK: - items[]

struct ContractItem: Codable, Sendable, Hashable {
    var postId: String
    var legoScreen: LegoScreen
    var topicId: String
    var places: [ExtractedPlace]?
    var tip: ExtractedTip?
    var routine: ExtractedRoutine?
}

enum PlaceType: String, Codable, Sendable, CaseIterable, Identifiable {
    case food, cafe, bakery, bar, other

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlaceType(rawValue: raw) ?? .other
    }

    var emoji: String {
        switch self {
        case .food: "🍽️"
        case .cafe: "☕️"
        case .bakery: "🥐"
        case .bar: "🍸"
        case .other: "📍"
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        case .bakery: "birthday.cake.fill"
        case .bar: "wineglass.fill"
        case .other: "mappin"
        }
    }

    var title: String {
        switch self {
        case .food: "Food"
        case .cafe: "Café"
        case .bakery: "Bakery & dessert"
        case .bar: "Bar"
        case .other: "Other"
        }
    }
}

enum EvidenceKind: String, Codable, Sendable {
    case locationTag = "location_tag", pinEmoji = "pin_emoji", mention, address, plainText = "plain_text", collectionOnly = "collection_only"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EvidenceKind(rawValue: raw) ?? .plainText
    }

    /// Strong evidence can be placed without asking (confirm.md triage).
    var isStrong: Bool {
        switch self {
        case .locationTag, .pinEmoji, .mention, .address: true
        case .plainText, .collectionOnly: false
        }
    }
}

struct ExtractedPlace: Codable, Sendable, Hashable {
    var name: String
    var handle: String?
    var areaHint: String?
    var address: String?
    var type: PlaceType
    var reason: String?
    var evidence: String
    var evidenceKind: EvidenceKind
    var confidence: Confidence
}

enum TipType: String, Codable, Sendable {
    case tool, technique, tutorial, list, idea

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TipType(rawValue: raw) ?? .idea
    }
}

struct ExtractedTip: Codable, Sendable, Hashable {
    var title: String
    var gist: String?
    var tryPrompt: String?
    var tipType: TipType
    var keyPoints: [String]
    var ctaKeyword: String?
    var isThin: Bool
}

enum BodyArea: String, Codable, Sendable, CaseIterable, Identifiable {
    case neck, shoulders, upperBack = "upper_back", lowerBack = "lower_back", hips, knees, ankles, core, fullBody = "full_body"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neck: "Neck"
        case .shoulders: "Shoulders"
        case .upperBack: "Upper back"
        case .lowerBack: "Lower back"
        case .hips: "Hips"
        case .knees: "Knees"
        case .ankles: "Ankles"
        case .core: "Core"
        case .fullBody: "Full body"
        }
    }

    var symbol: String {
        switch self {
        case .neck: "person.bust"
        case .shoulders: "figure.arms.open"
        case .upperBack: "figure.cooldown"
        case .lowerBack: "figure.flexibility"
        case .hips: "figure.pilates"
        case .knees: "figure.walk"
        case .ankles: "shoeprints.fill"
        case .core: "figure.core.training"
        case .fullBody: "figure.mixed.cardio"
        }
    }
}

enum FitnessGoal: String, Codable, Sendable, CaseIterable, Identifiable {
    case painRelief = "pain_relief", mobility, posture, strength, recovery

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FitnessGoal(rawValue: raw) ?? .mobility
    }

    var title: String {
        switch self {
        case .painRelief: "Pain relief"
        case .mobility: "Mobility"
        case .posture: "Posture"
        case .strength: "Strength"
        case .recovery: "Recovery"
        }
    }
}

enum Equipment: String, Codable, Sendable {
    case none, mat, band, foamRoller = "foam_roller", dumbbell, other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Equipment(rawValue: raw) ?? .other
    }

    var title: String {
        switch self {
        case .none: "No equipment"
        case .mat: "Mat"
        case .band: "Band"
        case .foamRoller: "Foam roller"
        case .dumbbell: "Dumbbell"
        case .other: "Other gear"
        }
    }
}

struct Exercise: Codable, Sendable, Hashable {
    var name: String
    var reps: Int?
    var sets: Int?
    var holdSeconds: Int?
    var eachSide: Bool

    /// "10 each side", "30s hold", "3 × 10".
    var detail: String? {
        var parts: [String] = []
        if let sets, let reps { parts.append("\(sets) × \(reps)") } else if let reps { parts.append("\(reps)") }
        if let holdSeconds { parts.append("\(holdSeconds)s hold") }
        if eachSide { parts.append(parts.isEmpty ? "each side" : "each side") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    init(name: String, reps: Int? = nil, sets: Int? = nil, holdSeconds: Int? = nil, eachSide: Bool = false) {
        self.name = name
        self.reps = reps
        self.sets = sets
        self.holdSeconds = holdSeconds
        self.eachSide = eachSide
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        reps = try? c.decodeIfPresent(Int.self, forKey: .reps)
        sets = try? c.decodeIfPresent(Int.self, forKey: .sets)
        holdSeconds = try? c.decodeIfPresent(Int.self, forKey: .holdSeconds)
        eachSide = (try? c.decodeIfPresent(Bool.self, forKey: .eachSide)) ?? false
    }
}

struct ExtractedRoutine: Codable, Sendable, Hashable {
    var title: String
    var bodyAreas: [BodyArea]
    var goal: FitnessGoal
    var exercises: [Exercise]
    var estMinutes: Int?
    var equipment: [Equipment]
    var doPrompt: String?
    var isThin: Bool
    var isPainRelated: Bool

    enum CodingKeys: String, CodingKey {
        case title, bodyAreas, goal, exercises, estMinutes, equipment, doPrompt, isThin, isPainRelated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        let areas = (try? c.decode([String].self, forKey: .bodyAreas)) ?? []
        bodyAreas = areas.compactMap(BodyArea.init(rawValue:))
        if bodyAreas.isEmpty { bodyAreas = [.fullBody] }
        goal = (try? c.decode(FitnessGoal.self, forKey: .goal)) ?? .mobility
        exercises = (try? c.decode([Exercise].self, forKey: .exercises)) ?? []
        estMinutes = try? c.decodeIfPresent(Int.self, forKey: .estMinutes)
        equipment = (try? c.decode([Equipment].self, forKey: .equipment)) ?? []
        doPrompt = try c.decodeIfPresent(String.self, forKey: .doPrompt)
        isThin = (try? c.decode(Bool.self, forKey: .isThin)) ?? false
        isPainRelated = (try? c.decode(Bool.self, forKey: .isPainRelated)) ?? false
    }

    init(title: String, bodyAreas: [BodyArea], goal: FitnessGoal, exercises: [Exercise] = [], estMinutes: Int? = nil,
         equipment: [Equipment] = [], doPrompt: String? = nil, isThin: Bool = false, isPainRelated: Bool = false) {
        self.title = title
        self.bodyAreas = bodyAreas
        self.goal = goal
        self.exercises = exercises
        self.estMinutes = estMinutes
        self.equipment = equipment
        self.doPrompt = doPrompt
        self.isThin = isThin
        self.isPainRelated = isPainRelated
    }
}
