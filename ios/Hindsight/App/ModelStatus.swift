import Foundation
import FoundationModels

/// Which of Apple's models the app can use right now.
enum ModelStatus: String, Sendable {
    case cloud = "Private Cloud Compute"
    case onDevice = "On-device"
    case none = "None"

    static var current: ModelStatus {
#if compiler(>=6.3)
        if #available(iOS 27, *), PrivateCloudComputeLanguageModel().isAvailable { return .cloud }
#endif
        return SystemLanguageModel.default.isAvailable ? .onDevice : .none
    }
}
