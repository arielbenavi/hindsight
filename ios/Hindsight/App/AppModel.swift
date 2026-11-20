import Foundation
import Observation

/// The app's root state: which dataset is loaded, the views' layout, and the
/// per-screen stores. Everything user-owned is saved under the dataset's folder.
/// There's no setup to go through: the user's saves are sorted in the background
/// and the layout follows from the sorted topics (`autoSetup`).
@Observable
@MainActor
final class AppModel {
    static let datasetKey = "selectedDataset"

    private(set) var datasets: [Dataset]
    private(set) var dataset: Dataset?
    private(set) var data: HindsightData?
    private(set) var loadError: String?

    /// Which topics each view (Map, Learn, Fitness) shows. Set automatically.
    private(set) var layout: LayoutConfig?
    /// Set once the saves were sorted and the layout set, the first time.
    private(set) var setupDone = false
    /// Bumped every time sorting starts, so Home can follow the new run.
    private(set) var sortRuns = 0

    private(set) var places: PlaceStore
    private(set) var practice: PracticeStore
    private(set) var learn: LearnCatalog?
    private(set) var fitness: FitnessCatalog?

    /// The user's own imports (Ariel's store), sorted by `engine` into the "me" dataset.
    let store: SavedPostStore?
    private(set) var engine: SortEngine?
    private var setupTask: Task<Void, Never>?

    private let persist: Bool
    private var layoutFile: JSONFile<LayoutConfig>
    private var flagsFile: JSONFile<Flags>

    private struct Flags: Codable {
        /// Older builds finished setup with a place check; kept so their flags still read.
        var confirmationDone = false
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
        let initial = useMySaves ? mine : Self.sample(in: datasets, selected: selected)
        if let initial { select(initial) }
        // Before any screen appears: my saves but none imported → back to Connect.
        if persist, isMySaves, !setupDone, myPosts.isEmpty {
            UserDefaults.standard.set(false, forKey: OnboardingModel.completedKey)
        }
        autoSetup()
    }

    /// The bundled sample ("Just looking?"): the last one picked, else Reut's.
    static func sample(in datasets: [Dataset] = Dataset.bundled(),
                       selected: String? = UserDefaults.standard.string(forKey: AppModel.datasetKey)) -> Dataset? {
        let bundled = datasets.filter { !$0.isMine }
        return bundled.first { $0.id == selected } ?? bundled.first { $0.id == "reut" } ?? bundled.first
    }

    /// Load a dataset. Each dataset keeps its own layout and user state.
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
        setupDone = flags?.setupDone ?? flags?.confirmationDone ?? false
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

    /// Point the screens at the layout's topics (or the natural ones until it's
    /// set). Every place topic is matched, even below the Map's threshold, so a
    /// small place topic still opens on a map from its topic page.
    private func applyLayout() {
        guard let data else { learn = nil; fitness = nil; return }
        let natural = LayoutRules.propose(data)
        let tabs = layout?.tabs ?? natural.tabs
        let topics = { (s: LegoScreen) in tabs.first { $0.legoScreen == s }?.topicIDs ?? [] }
        places.setMapTopics(data.topics.filter { $0.legoScreen == .map }.map(\.id))
        learn = LearnCatalog(data: data, topicIDs: topics(.learn))
        fitness = FitnessCatalog(data: data, topicIDs: topics(.fitness))
    }

    /// The view for a screen: the layout's tab, or every topic of that kind.
    func tab(for screen: LegoScreen) -> TabConfig {
        var tab = layout?.tab(for: screen)
            ?? TabConfig(legoScreen: screen, topicIDs: data?.topics.filter { $0.legoScreen == screen }.map(\.id) ?? [])
        tab.title = screen.homeTitle
        return tab
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
    }

    // MARK: - Setup, without a setup screen

    /// Sorts the user's saves in the background and, once enough are sorted, writes
    /// the file and sets the natural layout. Sample data gets its layout at once.
    /// Home shows the raw saves meanwhile, so nothing waits on this.
    private func autoSetup() {
        guard isMySaves else {
            if data != nil, layout == nil || !setupDone { finishAutoSetup() }
            return
        }
        guard persist, !myPosts.isEmpty else { return }
        if setupDone {
            // Saves imported since: they join the topics when sorted (`rewriteMySaves`).
            // A cache from an older build may also have topics to name.
            if hasNewImports || sortEngine().hasUnnamedHints(myPosts) {
                startSorting()
            } else {
                // Saves sorted without a model (no Apple Intelligence then): ask it now if it's here.
                let engine = sortEngine(), posts = myPosts
                Task { [weak self] in if await engine.canImproveFallbacks(posts) { self?.startSorting() } }
            }
            return
        }
        guard setupTask == nil else { return }
        startSorting()
        setupTask = Task { [weak self] in
            guard let stream = self?.sortProgress() else { return }
            let clock = ContinuousClock()
            let started = clock.now
            // Most sorted, or half after 20 s (SortProgress.shouldHandOff).
            for await progress in stream where progress.shouldHandOff(after: clock.now - started) { break }
            guard let self else { return }
            _ = await buildMySaves()
            finishAutoSetup()
            setupTask = nil
        }
    }

    private func finishAutoSetup() {
        guard let data else { return }
        if layout == nil { approve(LayoutRules.propose(data).config()) }
        finishSetup()
    }

    /// New imports (Sources, a server pull): sort them in the background. With the
    /// sample showing, the user's first own saves switch Home over to them.
    func importsChanged() {
        guard persist, !myPosts.isEmpty else { return }
        if !isMySaves {
            switchToMySaves()
            return
        }
        autoSetup()
        // First sort still running: it picks the newcomers up right after (SortEngine.start).
        if setupTask != nil { startSorting() }
    }

    /// From the sample to the user's own saves, in place (what "Run setup again" did).
    private func switchToMySaves() {
        let mine = Dataset.mine()
        if !datasets.contains(where: \.isMine) { datasets.insert(mine, at: 0) }
        UserDefaults.standard.set(OnboardingChoice.mySaves.rawValue, forKey: Self.setupSourceKey)
        DebugLog.write("own saves arrived: switching from the sample to my saves")
        select(mine)
        autoSetup()
    }

    /// `HindsightApp`'s record of what the user started with ("mine" or empty = sample).
    static let setupSourceKey = "setupSource"

    // MARK: - Server sync

    private var lastPull: Date?
    private var pulling = false
    nonisolated static let pullInterval: TimeInterval = 60

    /// On launch and every time the app comes to the front: make this install's
    /// account if needed, then pull what the server has (Muse, WhatsApp bot) into
    /// the store. At most once a minute; failures only go to the debug log.
    func syncWithServer(now: Date = .now) async {
        guard persist, let store, ServerSync.isConfigured, !pulling, !Self.isUnitTestHost else { return }
        guard Self.isPullDue(last: lastPull, now: now) else { return }
        pulling = true
        defer { pulling = false }
        lastPull = now
        await MuseConnector.ensureAccount()
        do {
            // New saves land in the store; Home sees them and calls `importsChanged`.
            _ = try await ServerSync.pull(into: store)
        } catch {
            DebugLog.write("server pull failed: \(error.localizedDescription)")
        }
    }

    /// The app hosting the unit tests: no network from there.
    private static var isUnitTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    nonisolated static func isPullDue(last: Date?, now: Date, interval: TimeInterval = pullInterval) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
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
        sortRuns += 1
        sortEngine().start(myPosts) { [weak self] in
            Task { await self?.rewriteMySaves() }
        }
    }

    func sortProgress() -> AsyncStream<SortProgress> { sortEngine().progressStream() }

    /// Every save, newest first: the user's imports (the source of truth, sorted
    /// or not; topics come from the sorted file), or the sample's.
    var allPosts: [ContractPost] { isMySaves ? myPosts : (data?.posts ?? []) }

    /// Imports the sorted file doesn't have yet (after setup).
    var hasNewImports: Bool {
        guard let data else { return false }
        return !Set(myPosts.map(\.id)).isSubset(of: Set(data.posts.map(\.id)))
    }

    /// "Run setup again" (Sources, beta menu): forget the sorted file and layout so
    /// onboarding can run again. Keeps the imports and the sort cache.
    static func resetMySetup() {
        let directory = Dataset.mine().url.deletingLastPathComponent()
        for name in ["hindsight.json", "layout.json", "flags.json"] {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    /// Enough is sorted: write the user's contract file from what's sorted so far
    /// and load it. The rest joins later (`rewriteMySaves`).
    func buildMySaves() async -> HindsightData? {
        await writeMySaves()
        guard let mine = datasets.first(where: \.isMine) else { return nil }
        select(mine)
        places.startMatching()
        return data
    }

    /// Late posts or new details: rewrite the file and reload (Home follows), once
    /// the first file is in.
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

    /// The layout is set: load anything sorted since the first file.
    func finishSetup() {
        setupDone = true
        flagsFile.save(Flags(confirmationDone: true, setupDone: true))
        if isMySaves { Task { await rewriteMySaves() } }
    }

    /// Dev: forget the layout and all user state for this dataset.
    func resetCurrentDataset() {
        guard let dataset else { return }
        if persist, let directory = JSONFile<LayoutConfig>.directory(for: dataset.id) {
            try? FileManager.default.removeItem(at: directory)
        }
        select(dataset)
        autoSetup()
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
