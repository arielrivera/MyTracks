import Foundation

struct ResourceUsage: Equatable {
    let cpuPercent: Double
    let memoryGB: Double
}

enum SeparationState: Equatable {
    case idle
    case preparing
    case downloadingModels(progress: Double, modelName: String)
    case separating(progress: Double, currentStem: String, resources: ResourceUsage?)
    case completed
    case cancelled
    case failed(String)
    
    var isActive: Bool {
        switch self {
        case .idle, .completed, .cancelled, .failed:
            return false
        case .preparing, .downloadingModels, .separating:
            return true
        }
    }
    
    var progressValue: Double {
        switch self {
        case .separating(let progress, _, _):
            return progress
        case .downloadingModels(let progress, _):
            return progress
        default:
            return 0
        }
    }
    
    var statusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .preparing:
            return "Preparing..."
        case .downloadingModels(_, let modelName):
            return "Downloading \(modelName)..."
        case .separating(_, let stem, _):
            return "Separating \(stem)..."
        case .completed:
            return "Complete!"
        case .cancelled:
            return "Cancelled"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }
    
    var resources: ResourceUsage? {
        switch self {
        case .separating(_, _, let resources):
            return resources
        default:
            return nil
        }
    }
}
