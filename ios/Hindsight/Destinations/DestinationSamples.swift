#if DEBUG
import Foundation

/// Dev: a handful of saves that exercise every destination (recipes with ingredient
/// lists, places with location tags, events with a date ahead, films), three of each
/// so each forms its own topic. Beta menu → "Add destination test saves".
enum DestinationSamples {
    static func posts(now: Date = .now) -> [SavedPost] {
        let day: TimeInterval = 86_400
        func post(_ id: String, _ caption: String, author: String, tags: [String], ago: Double,
                  place: SavedPost.LocationTag? = nil) -> SavedPost {
            SavedPost(platform: .instagram, url: URL(string: "https://www.instagram.com/p/HSDEST\(id)/")!, kind: .reel,
                      author: author, caption: caption, hashtags: tags, savedAt: now.addingTimeInterval(-ago * day),
                      locationTag: place, source: .igExport)
        }
        // Dates written out in English ("Saturday, December 5, 2026"), always ahead of today.
        func written(_ days: Int) -> String {
            let date = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US")
            f.dateFormat = "EEEE, MMMM d, yyyy"
            return f.string(from: date)
        }
        let soonText = written(15), later = written(25)
        func yearsAgo(_ years: Int) -> Double {
            let then = Calendar.current.date(byAdding: .year, value: -years, to: now) ?? now
            return now.timeIntervalSince(then) / day
        }
        return [
            post("R1", """
                Crispy miso pasta in 15 minutes 🍝

                Ingredients:
                - 200g spaghetti
                - 2 tbsp white miso
                - 3 tbsp butter
                - 2 cloves garlic
                - parmesan, to serve

                Method:
                Boil the pasta in salted water, keep a cup of the water, then toss everything together.
                #recipe #pasta #dinner
                """, author: "chef.anna", tags: ["recipe", "pasta", "dinner"], ago: 120),
            post("R2", "The 3-ingredient banana bread everyone asks for\n2 ripe bananas\n1 cup oat flour\n2 eggs\n#recipe #baking",
                 author: "bakewithmo", tags: ["recipe", "baking"], ago: 200),
            post("R3", "Weeknight dal that tastes like a hug 💛 full recipe on my site #recipe #cooking #food",
                 author: "chef.anna", tags: ["recipe", "cooking", "food"], ago: 260),
            post("P1", "Best cacio e pepe in the city, no contest 🍝 #nycrestaurants #restaurant", author: "eatwithjo",
                 tags: ["nycrestaurants", "restaurant"], ago: 90,
                 place: .init(name: "Lilia", address: "567 Union Ave, Brooklyn, NY")),
            post("P2", "Hidden omakase counter, 8 seats only #restaurant #sushi", author: "eatwithjo",
                 tags: ["restaurant", "sushi"], ago: 150, place: .init(name: "Sushi Ishikawa", address: "Upper East Side, NY")),
            post("P3", "This cafe has the best cardamom buns #cafe #restaurant", author: "coffeemaps",
                 tags: ["cafe", "restaurant"], ago: 300, place: .init(name: "Fabrique Bakery", address: "Meatpacking, NY")),
            post("E1", "Rooftop jazz night 🎷 \(soonText) at 8pm. Tickets in bio #events #nightlife #jazz", author: "elsewhere.bk",
                 tags: ["events", "nightlife", "jazz"], ago: 40, place: .init(name: "Elsewhere", address: "Brooklyn, NY")),
            post("E2", "Night market is back every Saturday this summer #events #nightlife", author: "queensnightmarket",
                 tags: ["events", "nightlife"], ago: 70, place: .init(name: "Queens Night Market", address: "Flushing Meadows, NY")),
            post("E3", "Sample sale ends \(later) — 60% off everything #events #sale",
                 author: "deals.nyc", tags: ["events", "sale"], ago: 60),
            post("M1", "Perfect Days (2023), Wim Wenders. The quietest, best film I saw this year #movies #film", author: "filmthoughts",
                 tags: ["movies", "film"], ago: 110),
            post("M2", "5 movies to watch if you loved Past Lives #movies #film #netflix", author: "filmthoughts",
                 tags: ["movies", "film", "netflix"], ago: 180),
            post("M3", "Aftersun broke me. Watch it with someone you love #movies #film", author: "cinemaclub",
                 tags: ["movies", "film"], ago: 240),
            // Saved on this day in earlier years: Today's anniversary picks come first,
            // so "New Today set" shows Today's action under the card.
            post("P4", "L'Industrie: worth the line, get the burrata slice #restaurant #pizza", author: "eatwithjo",
                 tags: ["restaurant", "pizza"], ago: yearsAgo(1), place: .init(name: "L'Industrie Pizzeria", address: "Williamsburg, NY")),
            post("R4", "Shakshuka for two\nIngredients:\n- 4 eggs\n- 1 can crushed tomatoes\n- 1 red pepper\n- 1 tsp cumin\n#recipe #breakfast",
                 author: "chef.anna", tags: ["recipe", "breakfast"], ago: yearsAgo(2)),
        ]
    }
}
#endif
