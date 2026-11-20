import Foundation

/// Pulls a shopping list out of a recipe caption. Deterministic, no model.
///
/// 1. With a heading ("Ingredients:", "You'll need", "מצרכים"): the lines after it,
///    until a method heading ("Instructions", "Method", "אופן הכנה"), hashtags or a
///    long sentence. An inline list ("Ingredients: flour, eggs, milk") splits on commas.
/// 2. Without one: lines that start with a quantity and a unit ("2 cups flour",
///    "200g butter", "½ tsp salt", "2 כוסות קמח"), or short bullet lines (-, •, *,
///    an emoji) next to them. Needs at least two, so a stray "1 thing I love" isn't a list.
/// Bullets, numbering and leading emoji come off; sub-headings ("For the sauce:") are skipped.
enum IngredientParser {
    static let maxItems = 40

    static let headings = ["ingredients", "ingredient", "you'll need", "you will need", "what you need", "shopping list",
                           "מצרכים", "המצרכים", "רכיבים", "הרכיבים", "חומרים", "מה צריך"]
    static let stops = ["instructions", "instruction", "method", "directions", "steps", "preparation", "how to make",
                        "to make", "prep", "assembly", "אופן הכנה", "אופן ההכנה", "הוראות", "הכנה", "שלבים", "איך מכינים"]
    static let units = ["cup", "cups", "c", "tbsp", "tbs", "tablespoon", "tablespoons", "tsp", "teaspoon", "teaspoons",
                        "g", "gr", "gram", "grams", "kg", "ml", "l", "liter", "liters", "litre", "oz", "ounce", "ounces",
                        "lb", "lbs", "pound", "pounds", "pinch", "clove", "cloves", "can", "cans", "slice", "slices",
                        "handful", "stick", "sticks", "bunch", "pack", "package", "large", "medium", "small", "whole",
                        "כוס", "כוסות", "כף", "כפות", "כפית", "כפיות", "גרם", "קג", "ק״ג", "ק\"ג", "מל", "מ״ל", "מ\"ל",
                        "ליטר", "חבילה", "חבילת", "קורט", "שן", "שיני", "יחידות", "פרוסות"]
    private static let fractionChars: Set<Character> = ["½", "¼", "¾", "⅓", "⅔", "⅛", "⅜", "⅝", "⅞"]

    static func parse(_ caption: String?) -> [String] {
        guard let caption, !caption.isEmpty else { return [] }
        let lines = caption.components(separatedBy: .newlines)
        if let items = afterHeading(lines), !items.isEmpty { return finish(items) }
        return finish(loose(lines))
    }

    // MARK: - With a heading

    private static func afterHeading(_ lines: [String]) -> [String]? {
        guard let index = lines.firstIndex(where: { heading(in: $0) != nil }) else { return nil }
        var items: [String] = []
        // "Ingredients: flour, eggs, milk" on one line.
        if let rest = heading(in: lines[index]), !rest.isEmpty {
            items += rest.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "،" }).map { clean(String($0)) }
        }
        for raw in lines[(index + 1)...] {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if isStop(line) || line.hasPrefix("#") { break }
            let item = clean(line)
            if item.isEmpty { continue }
            if item.hasSuffix(":") { continue }            // "For the sauce:"
            if item.count > 90 { break }                   // a sentence: the method started
            items.append(item)
            if items.count >= maxItems { break }
        }
        return items
    }

    /// The text after an ingredients heading on its line ("" for a bare heading), or
    /// nil when the line isn't one.
    static func heading(in line: String) -> String? {
        let stripped = stripLeading(line).lowercased()
        for word in headings where stripped.hasPrefix(word) {
            var rest = stripped.dropFirst(word.count)
            // "Ingredients (serves 4):" — skip a parenthesis.
            if rest.hasPrefix(" (") || rest.hasPrefix("("), let close = rest.firstIndex(of: ")") {
                rest = rest[rest.index(after: close)...]
            }
            let trimmed = rest.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == ":" { return "" }
            if trimmed.hasPrefix(":") || trimmed.hasPrefix("-") || trimmed.hasPrefix("–") {
                // Keep the original casing of the inline list.
                let original = stripLeading(line)
                let offset = original.count - trimmed.count + 1
                return String(original.dropFirst(offset)).trimmingCharacters(in: .whitespaces)
            }
            // "Ingredients are the secret…" is a sentence, not a heading.
            return trimmed.split(separator: " ").count <= 2 && !trimmed.contains(where: \.isLetter) ? "" : nil
        }
        return nil
    }

    private static func isStop(_ line: String) -> Bool {
        let stripped = stripLeading(line).lowercased()
        guard stripped.split(separator: " ").count <= 5 else { return false }
        return stops.contains { stripped.hasPrefix($0) }
    }

    // MARK: - Without a heading

    private static func loose(_ lines: [String]) -> [String] {
        var items: [String] = []
        var quantities = 0
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("@") else { continue }
            let item = clean(line)
            guard !item.isEmpty, !item.hasSuffix(":") else { continue }
            if hasQuantity(item) {
                quantities += 1
                items.append(item)
            } else if hasBullet(line) || item.first?.isNumber == true, item.count <= 50, item.split(separator: " ").count <= 7 {
                items.append(item)  // "- salt", "🥚 3 eggs": only kept if real quantities say it's a list
            }
        }
        return quantities >= 2 ? items : []
    }

    /// Starts with a number or fraction followed by a unit ("2 cups", "200g", "1/2 tsp").
    static func hasQuantity(_ item: String) -> Bool {
        var rest = Substring(item)
        let number = rest.prefix { $0.isNumber || fractionChars.contains($0) || $0 == "/" || $0 == "." || $0 == "," || $0 == "-" }
        guard let first = number.first, first.isNumber || fractionChars.contains(first) else { return false }
        rest = rest.dropFirst(number.count)
        let word = rest.trimmingCharacters(in: .whitespaces)
            .prefix { $0.isLetter || $0 == "״" || $0 == "\"" }
            .lowercased()
        let unit = word.hasSuffix(".") ? String(word.dropLast()) : word
        return units.contains(unit)
    }

    private static func hasBullet(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        if "-•*▪◦·–—✓✔︎>".contains(first) { return true }
        if first.isNumber {
            // "1." / "2)" numbering (not "1.5 cups").
            let digits = line.prefix(while: \.isNumber)
            let after = line.dropFirst(digits.count)
            return (after.hasPrefix(". ") || after.hasPrefix(") "))
        }
        return isEmoji(first)
    }

    // MARK: - Cleaning

    /// Bullets, numbering ("1. "), leading emoji and spaces off; inner spaces collapsed.
    static func clean(_ line: String) -> String {
        var text = stripLeading(line)
        let digits = text.prefix(while: \.isNumber)
        let after = text.dropFirst(digits.count)
        if !digits.isEmpty, digits.count <= 2, after.hasPrefix(". ") || after.hasPrefix(") ") {
            text = stripLeading(String(after.dropFirst(2)))
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Drops leading characters that aren't letters, digits or fractions (bullets, emoji, spaces).
    private static func stripLeading(_ line: String) -> String {
        String(line.drop { !($0.isLetter || $0.isNumber || fractionChars.contains($0)) })
    }

    private static func isEmoji(_ c: Character) -> Bool {
        c.unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x2000) }
    }

    private static func finish(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        return items.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .;,")) }
            .filter { !$0.isEmpty && $0.count <= 90 && seen.insert($0.lowercased()).inserted }
            .prefix(maxItems).map { $0 }
    }
}
