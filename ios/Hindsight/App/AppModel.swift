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
    /// Set when the user taps "Open my app" at the end of the setup chat.
    private(set) var setupDone = false

    private(set) var places: PlaceStore
    private(set) var practice: PracticeStore
    private(set) var learn: LearnCatalog?
    private(set) var fitness: FitnessCatalog?

    /// The user's own imports (Ariel's store), sorted by `engine` into the "me" dataset.
    private let store: SavedPostStore?
    private(set) var engine: SortEngine?

    private let persist: Bool
    private var layoutFile: JSONFile<LayoutConfig>
    private var flagsFile: JSONFile<Flags>

    private struct Flags: Codable {
        var confirmationDone = false
        /// Missing in flags saved before the setup chat: those users finished
        /// setup when they finished confirmation.
        var setupDone: Bool?
    }

    /// `persist: false` keeps everything in memory (previews, tests).
    /// `useMySaves`: the user started with their own saves, so open the "me"
    /// dataset (sorted on the phone) instead of a bundled sample.
    init(datasets: [Dataset] = Dataset.bundled(), selected: String? = UserDefaults.standard.string(forKey: AppModel.datasetKey),
         persist: Bool = true, store: SavedPostStore? = nil, useMySaves: Bool = false) {
        let mine = Dataset.mine()
        let hasMine = useMySaves || FileManager.default.fileExists(atPath: mine.url.path(percentEncoded: false))
        self.datasets = hasMine ? [mine] + datasets : datasets
        self.store = store
        self.persist = persist
        let empty = JSONFile<LayoutConfig>(name: "layout", directory: nil)
        layoutFile = empty
        flagsFile = JSONFile(name: "flags", directory: nil)
        places = PlaceStore(directory: nil, data: nil)
        practice = PracticeStore(directory: nil)
        let initial = useMySaves ? mine
            : (datasets.first { $0.id == selected } ?? datasets.first { $0.id == "reut" } ?? datasets.first)
        if let initial { select(initial) }
        // Before any screen appears: my saves but none imported → back to Connect;
        // imports changed mid-setup → the setup chat starts over on the new set.
        if persist, isMySaves, !setupDone {
            if myPosts.isEmpty {
                UserDefaults.standard.set(false, forKey: OnboardingModel.completedKey)
            } else if mySavesAreOutdated {
                restartMySetup()
            }
        }
    }

    /// Switch testers' data. Each dataset keeps its own layout and user state.
    func select(_ dataset: Dataset) {
        self.dataset = dataset
        if persist { UserDefaults.standard.set(dataset.id, forKey: Self.datasetKey) }
        do {
            // "me" has no file until the sort engine writes one (end of reading).
            if dataset.isMine && !FileManager.default.fileExists(atPath: dataset.url.path(percentEncoded: false)) {
                data = nil
            } else {
                data = try HindsightData.load(from: dataset.url)
            }
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
        let flags = flagsFile.load()
        confirmationDone = flags?.confirmationDone ?? false
        setupDone = flags?.setupDone ?? confirmationDone
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
        if isMySaves {
            // Tips and routines get their details in the background (places are done).
            let posts = myPosts
            Task { [weak self] in
                guard let engine = self?.engine, await engine.enrich(posts) > 0 else { return }
                await self?.rewriteMySaves()
            }
        }
        if !layout.hasMap { finishConfirmation() }
    }

    // MARK: - My saves (the sort engine)

    var isMySaves: Bool { dataset?.isMine ?? false }

    /// The user's own imports, newest first, without the bundled seed.
    var myPosts: [ContractPost] { ContractPost.userPosts(from: store?.posts ?? []) }

    private func sortEngine() -> SortEngine {
        if let engine { return engine }
        let engine = SortEngine(backend: AppleSortBackend(), directory: persist ? JSONFile<LayoutConfig>.directory(for: Dataset.mineID) : nil)
        self.engine = engine
        return engine
    }

    /// Start (or resume) sorting the user's saves. Safe to call again.
    func startSorting() {
        sortEngine().start(myPosts) { [weak self] in
            Task { await self?.rewriteMySaves() }
        }
    }

    func sortProgress() -> AsyncStream<SortProgress> { sortEngine().progressStream() }

    /// The sorted file no longer matches the user's imports (they added or
    /// removed saves mid-setup): the chat should start over on the new set.
    var mySavesAreOutdated: Bool {
        guard isMySaves, !setupDone, let data else { return false }
        return Set(data.posts.map(\.id)) != Set(myPosts.map(\.id))
    }

    /// Start the setup chat over on the current imports. The sort cache stays, so
    /// posts sorted before aren't sorted again.
    func restartMySetup() {
        guard let mine = datasets.first(where: \.isMine) else { return }
        for name in ["hindsight.json", "setup-chat.json", "layout.json", "flags.json"] {
            try? FileManager.default.removeItem(at: mine.url.deletingLastPathComponent().appending(path: name))
        }
        select(mine)
    }

    /// End of reading: write the user's contract file from what's sorted so far
    /// and load it. The rest joins later (`rewriteMySaves`).
    func buildMySaves() async -> HindsightData? {
        await writeMySaves()
        guard let mine = datasets.first(where: \.isMine) else { return nil }
        select(mine)
        places.startMatching()
        return data
    }

    /// Late posts or new details: rewrite the file; reload only once the user is
    /// in the app, so nothing shifts under the setup chat.
    private func rewriteMySaves() async {
        guard isMySaves, data != nil else { return }
        await writeMySaves()
        if setupDone, let mine = datasets.first(where: \.isMine) {
            select(mine)
            places.startMatching()
        }
    }

    private func writeMySaves() async {
        let posts = myPosts
        let platforms = Array(Set(posts.map(\.platform.rawValue))).sorted()
        let file = await sortEngine().assemble(posts, user: ContractUser(handle: "me", platforms: platforms))
        let url = Dataset.mine().url
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.encoded().write(to: url, options: .atomic)
        } catch {
            DebugLog.write("couldn't write my saves: \(error)")
        }
    }

    func finishConfirmation() {
        confirmationDone = true
        saveFlags()
    }

    /// End of the setup chat: show the tabs (with anything sorted since the proposal).
    func finishSetup() {
        finishConfirmation()
        setupDone = true
        saveFlags()
        if isMySaves { Task { await rewriteMySaves() } }
    }

    private func saveFlags() {
        flagsFile.save(Flags(confirmationDone: confirmationDone, setupDone: setupDone))
    }

    /// Bundled data (the sample saves) rather than the user's own sorted saves.
    var isSampleData: Bool { dataset.map { !$0.isMine } ?? false }

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
