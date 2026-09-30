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
        places = PlaceStore(directory: directory, data: data)
        practice = PracticeStore(directory: directory)
    }

    func approve(_ layout: LayoutConfig) {
        self.layout = layout
        layoutFile.save(layout)
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
    var everythingElse: [ContractPost] { data?.everythingElse(layout: layout) ?? [] }
}
