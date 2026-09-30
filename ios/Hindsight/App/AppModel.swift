import Foundation
import Observation

/// The app's root state: which dataset is loaded, the approved layout, and the
/// per-screen stores. Everything user-owned is saved under the dataset's folder.
@Observable
@MainActor
final class AppModel {
    static let datasetKey = "selectedDataset"

    private(set) var datasets: [Dataset]
    private(set) var dataset: Dataset?
    private(set) var data: HindsightData?
    private(set) var loadError: String?

    private(set) var layout: LayoutConfig?
    /// Set once the post-layout place confirmation pass is finished or skipped.
    private(set) var confirmationDone = false

    private(set) var places: PlaceStore
    private(set) var practice: PracticeStore
    private(set) var learn: LearnCatalog?
    private(set) var fitness: FitnessCatalog?

    private let persist: Bool
    private var layoutFile: JSONFile<LayoutConfig>
    private var flagsFile: JSONFile<Flags>

    private struct Flags: Codable { var confirmationDone = false }

    /// `persist: false` keeps everything in memory (previews, tests).
    init(datasets: [Dataset] = Dataset.bundled(), selected: String? = UserDefaults.standard.string(forKey: AppModel.datasetKey),
         persist: Bool = true) {
        self.datasets = datasets
        self.persist = persist
        let empty = JSONFile<LayoutConfig>(name: "layout", directory: nil)
        layoutFile = empty
        flagsFile = JSONFile(name: "flags", directory: nil)
        places = PlaceStore(directory: nil, data: nil)
        practice = PracticeStore(directory: nil)
        let initial = datasets.first { $0.id == selected } ?? datasets.first { $0.id == "reut" } ?? datasets.first
        if let initial { select(initial) }
    }

    /// Switch testers' data. Each dataset keeps its own layout and user state.
    func select(_ dataset: Dataset) {
        self.dataset = dataset
        if persist { UserDefaults.standard.set(dataset.id, forKey: Self.datasetKey) }
        do {
            data = try HindsightData.load(from: dataset.url)
            loadError = nil
        } catch {
            data = nil
            loadError = "Couldn't read \(dataset.url.lastPathComponent): \(error)"
            DebugLog.write(loadError ?? "")
        }
        let directory = persist ? JSONFile<LayoutConfig>.directory(for: dataset.id) : nil
        layoutFile = JSONFile(name: "layout", directory: directory)
        flagsFile = JSONFile(name: "flags", directory: directory)
        layout = layoutFile.load()
        confirmationDone = flagsFile.load()?.confirmationDone ?? false
        let bundledCache = Self.bundledMatchCache(for: dataset)
        places = PlaceStore(directory: directory, data: data, bundledCache: bundledCache)
        practice = PracticeStore(directory: directory)
        applyLayout()
    }

    /// `data/fixtures/<id>.matches.json`: a warm MapKit cache so first launch
    /// doesn't need hundreds of live searches. Optional.
    private static func bundledMatchCache(for dataset: Dataset) -> MatchCache? {
        let url = dataset.url.deletingLastPathComponent().appending(path: "\(dataset.id).matches.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MatchCache.self, from: data)
    }

    /// Point the screens at the approved layout's topics (or the natural ones
    /// while the proposal is still open, so matching can start early).
    private func applyLayout() {
        guard let data else { learn = nil; fitness = nil; return }
        let natural = LayoutRules.propose(data).draft
        let tabs = layout?.tabs ?? natural.tabs
        let topics = { (s: LegoScreen) in tabs.first { $0.legoScreen == s }?.topicIDs ?? [] }
        places.setMapTopics(layout == nil ? data.topics.filter { $0.legoScreen == .map }.map(\.id) : topics(.map))
        learn = LearnCatalog(data: data, topicIDs: topics(.learn))
        fitness = FitnessCatalog(data: data, topicIDs: topics(.fitness))
    }

    func approve(_ layout: LayoutConfig) {
        self.layout = layout
        layoutFile.save(layout)
        applyLayout()
        if !layout.hasMap { finishConfirmation() }
    }

    func finishConfirmation() {
        confirmationDone = true
        flagsFile.save(Flags(confirmationDone: true))
    }

    /// Dev: forget the layout and all user state for this dataset.
    func resetCurrentDataset() {
        guard let dataset else { return }
        if persist, let directory = JSONFile<LayoutConfig>.directory(for: dataset.id) {
            try? FileManager.default.removeItem(at: directory)
        }
        select(dataset)
    }

    /// Posts that show in no tab, for the Everything else sheet.
    var everythingElse: [ContractPost] {
        guard let data else { return [] }
        let notAPlace = places.notAPlacePostIDs
        let extra = notAPlace.isEmpty ? [] : data.posts.filter { notAPlace.contains($0.id) }
        return data.everythingElse(layout: layout) + extra
    }

    // MARK: - Reminders

    /// Rebuild all practice notifications (after opens and any reminder change).
    func rescheduleReminders() {
        var tabs: [ReminderScheduler.TabInput] = []
        if layout?.tab(for: .learn) != nil, let learn {
            tabs.append(.init(screen: .learn, practice: practice.screen(.learn), candidates: learn.candidates, config: .learn,
                              describe: { id in learn.tipsByID[id].map { ($0.title, $0.post.savedDate) } }))
        }
        if layout?.tab(for: .fitness) != nil, let fitness {
            tabs.append(.init(screen: .fitness, practice: practice.screen(.fitness), candidates: fitness.candidates, config: .fitness,
                              describe: { id in fitness.byID[id].map { ($0.title, $0.post.savedDate) } }))
        }
        let handled = tabs.allSatisfy { practice.isDoneForToday($0.screen) }
        Task { await ReminderScheduler.shared.reschedule(tabs: tabs, todayHandled: handled) }
    }
}
