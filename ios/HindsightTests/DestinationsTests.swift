import Foundation
import Testing
@testable import Hindsight

/// Destinations: which apply to a save, ingredient parsing, dates in captions,
/// Markdown export, Reminders (with the in-memory writer) and auto-route.
@MainActor
struct DestinationsTests {
    private func post(_ id: String, caption: String?, author: String = "chef.anna", saved: String? = "2026-03-01",
                      platform: Platform = .instagram) -> ContractPost {
        ContractPost(id: id, platform: platform, url: URL(string: "https://www.instagram.com/p/\(id)/")!, author: author,
                     caption: caption, savedAt: saved)
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private let found = DateFinder.Found(date: Date(timeIntervalSince1970: 1_800_000_000), hasTime: true, text: "Dec 5 at 8pm")

    // MARK: - Which destinations apply

    @Test func destinationsFollowTheJobAndTheContent() {
        // Go: Maps for the place.
        let go = Destinations.applicable(DestinationInput(job: .go, topicLabel: "Restaurants & cafés", placeQuery: "Lilia, Brooklyn"))
        #expect(go == [.maps(query: "Lilia, Brooklyn")])
        // A Go topic named like food ("Bakeries") is still places, not groceries.
        #expect(Destinations.applicable(DestinationInput(job: .go, topicLabel: "Bakeries", placeQuery: "Tartine")) == [.maps(query: "Tartine")])
        // No place to search: no Maps button.
        #expect(Destinations.applicable(DestinationInput(job: .go, topicLabel: "Travel")).isEmpty)
        // Do → recipes: Groceries. Do → workouts / other: To try.
        #expect(Destinations.applicable(DestinationInput(job: .doIt, topicLabel: "Food & recipes")) == [.reminders(.groceries)])
        #expect(Destinations.applicable(DestinationInput(job: .doIt, topicLabel: "מתכונים")) == [.reminders(.groceries)])
        #expect(Destinations.applicable(DestinationInput(job: .doIt, topicLabel: "Fitness & workouts")) == [.reminders(.toTry)])
        #expect(Destinations.applicable(DestinationInput(job: .doIt, topicLabel: "DIY & crafts")) == [.reminders(.toTry)])
        // An unsorted save whose caption lists ingredients is a recipe too.
        #expect(Destinations.applicable(DestinationInput(job: nil, topicLabel: nil, hasIngredients: true)) == [.reminders(.groceries)])
        // Watch / read / listen go to their list; Know also exports.
        #expect(Destinations.applicable(DestinationInput(job: .know, topicLabel: "Movies & TV")) == [.reminders(.watchlist), .export])
        #expect(Destinations.applicable(DestinationInput(job: .know, topicLabel: "Books")) == [.reminders(.readingList), .export])
        #expect(Destinations.applicable(DestinationInput(job: .know, topicLabel: "Music")) == [.reminders(.listenLater), .export])
        // Music production is learning, not listening.
        #expect(Destinations.applicable(DestinationInput(job: .learn, topicLabel: "Music production")) == [.export])
        // A date still ahead: Calendar, after the job's own destination.
        #expect(Destinations.applicable(DestinationInput(job: .go, topicLabel: "Events & nightlife", placeQuery: "Elsewhere",
                                                         date: found)) == [.maps(query: "Elsewhere"), .calendar(found)])
        #expect(Destinations.applicable(DestinationInput(job: .look, topicLabel: "Fashion & style", date: found)) == [.calendar(found)])
        // Keep close goes nowhere, whatever it holds.
        #expect(Destinations.applicable(DestinationInput(job: .keepClose, topicLabel: "Books", placeQuery: "x", date: found,
                                                         hasIngredients: true)).isEmpty)
        // At most three, best first.
        let many = Destinations.applicable(DestinationInput(job: .know, topicLabel: "Books", date: found))
        #expect(many == [.reminders(.readingList), .calendar(found), .export])
    }

    @Test func todayGetsTheBestNonExportAction() {
        #expect(Destinations.forToday(DestinationInput(job: .learn, topicLabel: "Coding")) == nil)
        #expect(Destinations.forToday(DestinationInput(job: .doIt, topicLabel: "Food & recipes", date: found)) == .reminders(.groceries))
        #expect(Destinations.forToday(DestinationInput(job: .go, topicLabel: "Travel", placeQuery: "Kyoto"))?.shortTitle == "Open in Maps")
        #expect(Destination.reminders(.groceries).shortTitle == "Add to Groceries")
    }

    @Test func bulkListsAndSentKeys() {
        #expect(Destinations.bulkList(topicLabel: "Movies & TV", job: .know) == .watchlist)
        #expect(Destinations.bulkList(topicLabel: "Food & recipes", job: .doIt) == .toTry)  // not everyone's ingredients
        #expect(Destinations.bulkList(topicLabel: "Coding", job: .learn) == nil)
        #expect(Destinations.bulkList(topicLabel: "Books", job: .keepClose) == nil)
        #expect(Destination.reminders(.watchlist).sentKey == "Watchlist")
        #expect(Destination.calendar(found).sentKey == "Calendar")
        #expect(Destination.maps(query: "x").sentKey == nil)
    }

    @Test func mapsLinksAndPlaceQuery() throws {
        let apple = Destinations.appleMapsURL("Lilia, Brooklyn")
        #expect(apple.host() == "maps.apple.com")
        #expect(URLComponents(url: apple, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Lilia, Brooklyn")
        let google = Destinations.googleMapsURL("Lilia")
        #expect(google.absoluteString == "https://www.google.com/maps/search/?api=1&query=Lilia")
        let place = ExtractedPlace(name: "Lilia", handle: nil, areaHint: "Williamsburg", address: nil, type: .food, reason: nil,
                                   evidence: "", evidenceKind: .locationTag, confidence: .high)
        #expect(Destinations.placeQuery(places: [place], locationTag: nil) == "Lilia, Williamsburg")
        let tag = ContractPost.LocationTag(name: "Café Kitsuné", address: "Paris", lat: nil, lng: nil)
        #expect(Destinations.placeQuery(places: [], locationTag: tag) == "Café Kitsuné, Paris")
        #expect(Destinations.placeQuery(places: [], locationTag: nil) == nil)
    }

    // MARK: - Ingredients

    @Test func ingredientsAfterAHeading() {
        let caption = """
        The crispiest miso pasta 🍝 save this!

        Ingredients (serves 2):
        - 200g spaghetti
        • 2 tbsp white miso
        🧈 3 tbsp butter
        1. 2 cloves garlic
        Parmesan, to serve
        For the topping:
        - chili flakes

        Method:
        1. Boil the pasta in salted water until al dente, then keep a cup of the water.
        #pasta #miso
        """
        #expect(IngredientParser.parse(caption) == ["200g spaghetti", "2 tbsp white miso", "3 tbsp butter", "2 cloves garlic",
                                                    "Parmesan, to serve", "chili flakes"])
    }

    @Test func ingredientsInlineLooseAndHebrew() {
        #expect(IngredientParser.parse("Ingredients: flour, 2 eggs, milk; salt") == ["flour", "2 eggs", "milk", "salt"])
        // No heading: quantity lines (and bullets next to them) count once there are two.
        let loose = "Best cookies ever\n2 cups flour\n1/2 tsp salt\n- chocolate chips\nBake at 180 for 12 minutes, so good."
        #expect(IngredientParser.parse(loose) == ["2 cups flour", "1/2 tsp salt", "chocolate chips"])
        // One stray number isn't a list.
        #expect(IngredientParser.parse("3 tips for better sleep\n- dark room\n- no phone") == [])
        let hebrew = """
        עוגת שוקולד מהירה
        מצרכים:
        2 כוסות קמח
        3 ביצים
        200 גרם שוקולד
        אופן ההכנה:
        מערבבים הכל ואופים
        """
        #expect(IngredientParser.parse(hebrew) == ["2 כוסות קמח", "3 ביצים", "200 גרם שוקולד"])
        #expect(IngredientParser.parse("Ingredients are the secret to a good life") == [])
        #expect(IngredientParser.parse(nil) == [])
    }

    @Test func groceriesDraftsFallBackToTheRecipe() {
        let recipe = post("R1", caption: "Miso pasta\nIngredients:\n- 200g spaghetti\n- 2 tbsp miso")
        let drafts = Destinations.drafts(for: recipe, list: .groceries)
        #expect(drafts.map(\.title) == ["200g spaghetti", "2 tbsp miso"])
        #expect(drafts.allSatisfy { $0.notes == "For: Miso pasta" && $0.url == recipe.url })
        // No ingredients found: one reminder with the recipe's title and link.
        let video = post("R2", caption: "The pasta that broke the internet #pasta #viral")
        let fallback = Destinations.drafts(for: video, list: .groceries)
        #expect(fallback.map(\.title) == ["The pasta that broke the internet"])
        #expect(fallback.first?.url == video.url)
        // Other lists: one item, due at the save's reminder.
        let due = at(2026, 11, 21, 20)
        #expect(Destinations.drafts(for: video, list: .toTry, due: due).first?.due == due)
        #expect(Destinations.title(for: post("R3", caption: nil)) == "@chef.anna's reel")
        // Calendar: the words before the date name the event.
        let gig = post("E1", caption: "Rooftop jazz night 🎷 Saturday, December 5, 2026 at 8pm. Tickets in bio")
        #expect(Destinations.eventTitle(for: gig, dateText: "Saturday, December 5, 2026 at 8pm") == "Rooftop jazz night")
        #expect(Destinations.eventTitle(for: gig, dateText: "not in it") == Destinations.title(for: gig))
    }

    // MARK: - Dates

    @Test func datesInCaptionsStillAhead() throws {
        let ref = at(2026, 11, 20, 9)
        let show = try #require(DateFinder.find(in: "Live at Elsewhere — Saturday, December 5, 2026 at 8pm. Tickets in bio",
                                                reference: ref))
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour], from: show.date)
        #expect(c.year == 2026 && c.month == 12 && c.day == 5 && c.hour == 20)
        #expect(show.hasTime)
        let sale = try #require(DateFinder.find(in: "Sale ends November 30, 2026! Everything 40% off", reference: ref))
        #expect(Calendar.current.component(.day, from: sale.date) == 30)   // "ends …" is a range from now: its end
        #expect(!sale.hasTime)
        let until = try #require(DateFinder.find(in: "Open call until 30.11.2026", reference: ref))
        #expect(Calendar.current.component(.day, from: until.date) == 30)
        // Past events and recipe fractions don't count.
        #expect(DateFinder.find(in: "Throwback to our trip on March 3, 2020", reference: ref) == nil)
        #expect(DateFinder.find(in: "1/2 cup sugar\n3/4 cup flour", reference: ref) == nil)
        #expect(DateFinder.find(in: "No dates here, just vibes", reference: ref) == nil)
        #expect(DateFinder.looksLikeADate("30.11.2026") && !DateFinder.looksLikeADate("1/2"))
        // Relative dates meant the day it was posted, not today.
        #expect(DateFinder.find(in: "Don't do these and you'll stay stiff. Fix it today", reference: ref) == nil)
        #expect(DateFinder.find(in: "Join us this Saturday at 8pm!", reference: ref) == nil)
        #expect(!DateFinder.looksLikeADate("tomorrow") && DateFinder.looksLikeADate("Dec 5"))
    }

    // MARK: - Markdown

    @Test func markdownForASaveAndATopic() {
        var p = post("M1", caption: "Sidechain compression in 60 seconds\nUse the kick as the key.", author: "mixwithmike",
                     saved: "2026-02-03")
        p.author.displayName = "Mike"
        let doc = MarkdownExporter.document(for: .init(post: p, transcript: "so first you route the kick", note: "try on the 808"),
                                            topic: "Music production", now: at(2026, 11, 20))
        #expect(doc == """
        # Sidechain compression in 60 seconds

        - **From:** @mixwithmike (Mike) · Instagram
        - **Link:** <https://www.instagram.com/p/M1/>
        - **Saved:** 2026-02-03
        - **Topic:** Music production

        ## My note

        try on the 808

        ## Caption

        Sidechain compression in 60 seconds
        Use the kick as the key.

        ## Transcript

        so first you route the kick

        Exported from hindsight on 2026-11-20.

        """)
        let topic = MarkdownExporter.document(topic: "Books", entries: [.init(post: post("B1", caption: "Read this"), transcript: nil, note: nil),
                                                                        .init(post: post("B2", caption: nil), transcript: nil, note: nil)],
                                              now: at(2026, 11, 20))
        #expect(topic.hasPrefix("# Books\n\n2 saves · Exported from hindsight on 2026-11-20.\n\n## Read this\n"))
        #expect(topic.contains("## @chef.anna's reel"))
        #expect(!topic.contains("### Transcript"))
        #expect(MarkdownExporter.fileName("Movies & TV: #1 / best?") == "Movies & TV 1 best.md")
    }

    // MARK: - Reminders (in-memory writer)

    @Test func remindersAddOnceAndRememberWhere() async {
        let writer = InMemoryRemindersWriter(access: .notDetermined)
        let sender = DestinationSender(writer: writer)
        let saves = SaveStateStore(directory: nil)
        let recipe = post("R1", caption: "Miso pasta\nIngredients:\n- 200g spaghetti\n- 2 tbsp miso\n- 2 tbsp miso")
        let now = at(2026, 11, 20)

        let first = await sender.send([recipe], to: .groceries, saves: saves, now: now)
        #expect(first == .added(.groceries, items: 2, saves: 1))
        #expect(first.message == "Added to Groceries · 2 items")
        #expect(await writer.requests == 1)                               // asked at the first tap
        #expect(await writer.items(in: "Groceries").map(\.title) == ["200g spaghetti", "2 tbsp miso"])
        #expect(saves.state("R1").sentDate("Groceries") == now)
        #expect(saves.state("R1").isRouted(now: now))

        // Second tap (or Send all): nothing added twice.
        #expect(await sender.send([recipe], to: .groceries, saves: saves, now: now) == .alreadyThere(.groceries))
        #expect(await writer.items(in: "Groceries").count == 2)

        // Another recipe with an overlapping item: the open "2 tbsp miso" isn't duplicated.
        let other = post("R2", caption: "Ingredients:\n- 2 tbsp miso\n- 1 lemon")
        #expect(await sender.send([other], to: .groceries, saves: saves, now: now) == .added(.groceries, items: 1, saves: 1))
        #expect(await writer.items(in: "Groceries").map(\.title) == ["200g spaghetti", "2 tbsp miso", "1 lemon"])

        // Bulk to another list: one per save, already-sent ones skipped.
        let film = post("F1", caption: "Perfect Days (2023) — Wim Wenders")
        #expect(await sender.send([film, film], to: .watchlist, saves: saves, now: now) == .added(.watchlist, items: 1, saves: 1))
        #expect(await sender.send([film], to: .watchlist, saves: saves, now: now).message == "Already in Watchlist")
    }

    @Test func remindersDeniedNeverWritesOrAsksInTheBackground() async {
        let denied = InMemoryRemindersWriter(access: .notDetermined, grantOnRequest: false)
        let saves = SaveStateStore(directory: nil)
        let p = post("D1", caption: "Dune")
        let result = await DestinationSender(writer: denied).send([p], to: .watchlist, saves: saves)
        #expect(result == .denied && !result.succeeded)
        #expect(saves.state("D1").sentTo == nil)
        // Background (auto-route) never shows the alert.
        let quiet = InMemoryRemindersWriter(access: .notDetermined)
        #expect(await DestinationSender(writer: quiet).send([p], to: .watchlist, saves: saves, askIfNeeded: false) == .denied)
        #expect(await quiet.requests == 0)
    }

    // MARK: - Auto-route

    @Test func autoRouteSendsOnlyNewSavesOnce() async {
        let route = AutoRoute(list: .watchlist, existing: ["old1", "old2"])
        var states: [String: SaveState] = ["gone": SaveState(status: .letGo)]
        #expect(AutoRouting.pending(topicPostIDs: ["new1", "old1", "gone", "new2", "old2"], route: route, states: states)
                == ["new1", "new2"])
        states["new1"] = SaveState(sentTo: ["Watchlist": .now])
        #expect(AutoRouting.pending(topicPostIDs: ["new1", "new2"], route: route, states: states) == ["new2"])

        // End to end through AppModel: a topic set to auto-route, two runs, one add.
        let app = AppModel(persist: false)
        let writer = InMemoryRemindersWriter(access: .granted)
        app.useRemindersWriter(writer)
        let library = app.library()
        let byID = Dictionary(app.allPosts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let titles = { (t: HomeTopic) in Set(t.postIDs.prefix(2).compactMap { byID[$0] }.map(Destinations.title)) }
        guard let topic = library.topics.first(where: { $0.kind != .other && $0.postIDs.count >= 3 && titles($0).count == 2 }) else {
            Issue.record("sample data has no topic with 3 saves"); return
        }
        let existing = Array(topic.postIDs.dropFirst(2))
        app.topicPrefs.setAutoRoute(AutoRoute(list: .toTry, existing: existing), for: topic.id)
        await app.runAutoRoutes()
        await app.runAutoRoutes()
        #expect(await writer.items(in: ReminderList.toTry.name).count == 2)
        #expect(topic.postIDs.prefix(2).allSatisfy { app.saves.state($0).sentDate(ReminderList.toTry.name) != nil })
        app.topicPrefs.setAutoRoute(nil, for: topic.id)
        #expect(app.topicPrefs.prefs.autoRoutes == nil)
    }

    // MARK: - Stored state stays readable

    @Test func olderFilesStillDecode() throws {
        let oldState = #"{"status":"done","shownInToday":2,"opens":1}"#
        let state = try JSONDecoder().decode(SaveState.self, from: Data(oldState.utf8))
        #expect(state.status == .done && state.sentTo == nil && state.routedAt == nil)
        let oldPrefs = #"{"jobs":{"ai:x":"go"},"moves":{}}"#
        let prefs = try JSONDecoder().decode(TopicPrefsStore.Prefs.self, from: Data(oldPrefs.utf8))
        #expect(prefs.jobs["ai:x"] == .go && prefs.autoRoutes == nil)
    }
}
