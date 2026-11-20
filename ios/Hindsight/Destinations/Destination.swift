import Foundation

/// A Reminders list hindsight writes to. Created the first time it's used.
enum ReminderList: String, Codable, Sendable, CaseIterable, Identifiable {
    case groceries = "Groceries"
    case toTry = "hindsight · To try"
    case watchlist = "Watchlist"
    case readingList = "Reading list"
    case listenLater = "Listen later"

    var id: String { rawValue }
    /// The list's name in Reminders, and the key in `SaveState.sentTo`.
    var name: String { rawValue }
    /// For buttons and confirmations: "Add to To try", "In Groceries".
    var shortName: String { self == .toTry ? "To try" : rawValue }

    var symbol: String {
        switch self {
        case .groceries: "cart.fill"
        case .toTry: "checklist"
        case .watchlist: "play.tv.fill"
        case .readingList: "book.fill"
        case .listenLater: "headphones"
        }
    }
}

/// Where a save can go to be useful: the app the person already uses for it.
/// Only what any app may write to, with no setup: Maps (a link), Reminders
/// (EventKit), Calendar (Apple's own add-event sheet) and the share sheet.
enum Destination: Hashable, Sendable, Identifiable {
    /// Apple Maps search for the save's place (Google Maps offered next to it).
    case maps(query: String)
    /// One reminder (or, for Groceries, one per ingredient) in a list.
    case reminders(ReminderList)
    /// Apple's add-event sheet, prefilled with the date found in the caption.
    case calendar(DateFinder.Found)
    /// Markdown through the share sheet (Notes, Files, Obsidian…).
    case export

    var id: String {
        switch self {
        case .maps: "maps"
        case .reminders(let list): "reminders:\(list.rawValue)"
        case .calendar: "calendar"
        case .export: "export"
        }
    }

    /// Key in `SaveState.sentTo` once it got there; nil for the ones that only open
    /// something (Maps, the share sheet), which can be done again any time.
    var sentKey: String? {
        switch self {
        case .reminders(let list): list.name
        case .calendar: Self.calendarKey
        case .maps, .export: nil
        }
    }

    static let calendarKey = "Calendar"

    var title: String {
        switch self {
        case .maps: "Open in Maps"
        case .reminders(.groceries): "Add ingredients to Groceries"
        case .reminders(let list): "Add to \(list.shortName)"
        case .calendar: "Add to Calendar"
        case .export: "Export as Markdown"
        }
    }

    /// Today's small action under the card.
    var shortTitle: String {
        switch self {
        case .reminders(let list): "Add to \(list.shortName)"
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .maps: "map.fill"
        case .reminders(let list): list.symbol
        case .calendar: "calendar.badge.plus"
        case .export: "square.and.arrow.up"
        }
    }

    /// Today offers it under the card (exporting one save isn't a "today" thing).
    var fitsToday: Bool { if case .export = self { false } else { true } }
}

/// What a save is about, for picking a list. From its topic's label (EN + HE).
enum DestinationSubject: Equatable, Sendable {
    case recipe, workout, watch, read, listen

    var list: ReminderList {
        switch self {
        case .recipe: .groceries
        case .workout: .toTry
        case .watch: .watchlist
        case .read: .readingList
        case .listen: .listenLater
        }
    }

    /// Checked in order; first match wins. Same keyword rules as `TopicJobs` (whole
    /// word, "stem*", "two words"). "Music production" is learning, not listening.
    static let table: [(DestinationSubject, [String])] = [
        (.recipe, ["food", "recipe*", "cooking", "cook", "baking", "bake*", "dessert*", "meal*", "dinner*",
                   "מתכון*", "מתכונ*", "בישול", "אוכל", "אפייה", "קינוח*"]),
        (.workout, ["workout*", "fitness", "exercise*", "stretch*", "yoga", "pilates", "gym", "אימון*", "כושר", "יוגה"]),
        (.watch, ["movie*", "film*", "tv", "series", "netflix", "cinema", "watchlist", "to watch", "סרט*", "סדרה", "סדרות"]),
        (.read, ["book*", "reading", "articles", "article", "papers", "novel*", "to read", "ספר*", "ספרים", "קריאה", "מאמר*"]),
        (.listen, ["music", "song*", "podcast*", "album*", "playlist*", "listen*", "מוזיקה", "שיר*", "פודקאסט*"]),
    ]

    static func of(label: String?) -> DestinationSubject? {
        guard let label else { return nil }
        let words = TopicJobs.Words(label)
        if words.has("music production") || words.has("production") { return nil }
        return table.first { _, keywords in keywords.contains(where: words.has) }?.0
    }
}

/// Everything the rules need to know about one save. Built by `AppModel.destinationInput`.
struct DestinationInput: Sendable {
    var job: TopicJob?
    var topicLabel: String?
    var legoScreen: LegoScreen?
    /// Place names already extracted (sorting) or the post's location tag: Maps searches the first.
    var placeQuery: String?
    /// A date in the caption that's still ahead (`DateFinder`).
    var date: DateFinder.Found?
    /// The caption has an ingredients list (`IngredientParser`).
    var hasIngredients = false
}

/// Which destinations apply to a save, best first, at most three. Pure.
enum Destinations {
    static let maxShown = 3

    static func applicable(_ input: DestinationInput) -> [Destination] {
        // Keep close stays put: nowhere else, ever.
        if input.job == .keepClose { return [] }
        var out: [Destination] = []

        // Places: only for Go topics (a recipe's location tag is usually just a city).
        if let query = input.placeQuery, input.job == .go || input.legoScreen == .map {
            out.append(.maps(query: query))
        }

        let subject = DestinationSubject.of(label: input.topicLabel)
            ?? (input.hasIngredients && (input.job == nil || input.job == .doIt) ? .recipe : nil)
        // A Go topic named like food ("Bakeries") is still places, not groceries.
        let listJobs: Set<TopicJob?> = [nil, .doIt, .learn, .know, .look]
        if let subject, listJobs.contains(input.job) {
            out.append(.reminders(subject.list))
        } else if input.job == .doIt || input.legoScreen == .fitness {
            out.append(.reminders(.toTry))
        }

        if let date = input.date { out.append(.calendar(date)) }

        if input.job == .learn || input.job == .know { out.append(.export) }

        var seen: Set<String> = []
        return Array(out.filter { seen.insert($0.id).inserted }.prefix(maxShown))
    }

    /// Today's secondary action: the best one that isn't an export.
    static func forToday(_ input: DestinationInput) -> Destination? {
        applicable(input).first(where: \.fitsToday)
    }

    /// "Send all to…" on a topic page: its Reminders list (recipes go to To try as a
    /// whole, not as everyone's ingredients), nil when no list fits.
    static func bulkList(topicLabel: String, job: TopicJob) -> ReminderList? {
        guard job != .keepClose else { return nil }
        switch DestinationSubject.of(label: topicLabel) {
        case .recipe?, .workout?: return .toTry
        case let subject?: return subject.list
        case nil: return job == .doIt ? .toTry : nil
        }
    }

    // MARK: - Maps

    static func appleMapsURL(_ query: String) -> URL {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "q", value: query)]
        return c.url!
    }

    /// Universal link: opens Google Maps if it's installed, else the web. (The
    /// `comgooglemaps://` check would need LSApplicationQueriesSchemes.)
    static func googleMapsURL(_ query: String) -> URL {
        var c = URLComponents(string: "https://www.google.com/maps/search/")!
        c.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: query)]
        return c.url!
    }

    /// The place to search: the first extracted place ("Name, area"), else the
    /// location tag's name and address.
    static func placeQuery(places: [ExtractedPlace], locationTag: ContractPost.LocationTag?) -> String? {
        if let place = places.first {
            let parts = [place.name, place.areaHint ?? place.address].compactMap { $0?.nilIfBlank }
            if !parts.isEmpty { return parts.joined(separator: ", ") }
        }
        if let tag = locationTag {
            let parts = [tag.name, tag.address].compactMap { $0?.nilIfBlank }
            if !parts.isEmpty { return parts.joined(separator: ", ") }
        }
        return nil
    }

    // MARK: - Reminders

    /// A save's title for a reminder: its first caption line (no hashtags), short.
    static func title(for post: ContractPost) -> String {
        let line = (post.firstLine ?? "")
            .split(separator: " ").filter { !$0.hasPrefix("#") }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return "\(post.byline)'s \(post.kind.rawValue)" }
        return line.count > 70 ? String(line.prefix(69)).trimmingCharacters(in: .whitespaces) + "…" : line
    }

    /// What to add for one save: for Groceries one item per ingredient (or the recipe
    /// itself when none were found); for any other list one item, due at the save's
    /// reminder if it has one ("Tonight", "Weekend").
    static func drafts(for post: ContractPost, list: ReminderList, due: Date? = nil) -> [ReminderDraft] {
        let title = title(for: post)
        if list == .groceries {
            let ingredients = IngredientParser.parse(post.caption)
            if !ingredients.isEmpty {
                return ingredients.map { ReminderDraft(title: $0, notes: "For: \(title)", url: post.url) }
            }
        }
        return [ReminderDraft(title: title, notes: "Saved from \(post.byline) · \(post.platform.displayName)", url: post.url, due: due)]
    }
}

extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
