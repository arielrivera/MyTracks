import Foundation
import os.log

private func engineLog(_ message: String) {
    os_log("%{public}@", log: .default, type: .debug, "[ArielSplitter Engine] \(message)")
}

/// Engine that handles AI-powered music source separation using Demucs.
final class SeparationEngine: @unchecked Sendable {
    private var isCancelled = false
    private var currentProcess: Process?
    private let lock = NSLock()
    
    func cancel() {
        lock.lock()
        isCancelled = true
        let process = currentProcess
        currentProcess = nil
        lock.unlock()
        process?.terminate()
    }
    
    func separate(
        fileURL: URL,
        categories: [StemCategory],
        outputDirectory: URL,
        progressHandler: @escaping @Sendable (Double, String, ResourceUsage?) -> Void
    ) async throws {
        engineLog("SeparationEngine.separate() called")
        
        lock.lock()
        isCancelled = false
        lock.unlock()
        
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        
        let scriptURL: URL
        if let resourceURL = Bundle.main.url(forResource: "separate", withExtension: "py") {
            engineLog("Found script in bundle: \(resourceURL.path)")
            scriptURL = resourceURL
        } else {
            let devPath = "/Users/arielrivera/Documents/GitHub/MyTracks/Ariel's Splitter/Sources/ArielSplitter/Resources/separate.py"
            engineLog("Using dev script path: \(devPath)")
            scriptURL = URL(fileURLWithPath: devPath)
        }
        
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            engineLog("Python script not found at \(scriptURL.path)")
            throw SeparationError.pythonError("Python script not found at \(scriptURL.path)")
        }
        
        let stemNames = categories.map { $0.demucsSourceName }
        let stemsData = try JSONSerialization.data(withJSONObject: stemNames)
        let stemsString = String(data: stemsData, encoding: .utf8)!
        
        let needs6Stems = categories.contains(where: { $0 == .guitar || $0 == .piano || $0 == .otherInstruments })
        let modelName = needs6Stems ? "htdemucs_6s" : "htdemucs"
        
        engineLog("Launching python3 \(scriptURL.path) separate \(fileURL.path) \(outputDirectory.path) \(stemsString) \(modelName)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path, "separate", fileURL.path, outputDirectory.path, stemsString, modelName]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        lock.lock()
        self.currentProcess = process
        lock.unlock()
        
        // Set up async stream of stdout lines on a dedicated serial queue
        let outputHandle = outputPipe.fileHandleForReading
        let parseQueue = DispatchQueue(label: "com.arielsplitter.output-parser")
        
        // Box to hold mutable parser state safely on parseQueue
        final class ParserState {
            var buffer = Data()
            var lastProgress: Double = 0
            var lastResources: ResourceUsage?
        }
        let state = ParserState()
        
        outputHandle.readabilityHandler = { handle in
            parseQueue.async {
                let data = handle.availableData
                guard !data.isEmpty else { return }
                
                state.buffer.append(data)
                
                // Process complete lines
                while let newlineRange = state.buffer.range(of: Data([10])) { // \n
                    let lineData = state.buffer.subdata(in: 0..<newlineRange.lowerBound)
                    state.buffer.removeSubrange(0..<newlineRange.upperBound)
                    
                    guard let line = String(data: lineData, encoding: .utf8) else { continue }
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    
                    if trimmed.hasPrefix("DEVICE:") {
                        engineLog("Separation using device: \(trimmed.dropFirst(7))")
                    } else if trimmed.hasPrefix("STATUS:") {
                        let status = String(trimmed.dropFirst(7))
                        engineLog("Status: \(status)")
                        let progress = state.lastProgress
                        let resources = state.lastResources
                        Task { @MainActor in
                            progressHandler(progress, status, resources)
                        }
                    } else if trimmed.hasPrefix("PROGRESS:") {
                        if let progress = Double(String(trimmed.dropFirst(9))) {
                            state.lastProgress = progress
                            let resources = state.lastResources
                            Task { @MainActor in
                                progressHandler(progress, "Processing...", resources)
                            }
                        }
                    } else if trimmed.hasPrefix("FILE:") {
                        let parts = trimmed.dropFirst(5).split(separator: ":", maxSplits: 2)
                        if parts.count >= 2 {
                            let stemName = String(parts[0])
                            let progress = state.lastProgress
                            let resources = state.lastResources
                            Task { @MainActor in
                                progressHandler(progress, "Saved \(stemName)...", resources)
                            }
                        }
                    } else if trimmed.hasPrefix("RESOURCE:") {
                        // Format: RESOURCE:CPU:12.3:MEM:4.56
                        let content = String(trimmed.dropFirst(9))
                        let parts = content.split(separator: ":")
                        if parts.count >= 4,
                           let cpu = Double(parts[1]),
                           let mem = Double(parts[3]) {
                            state.lastResources = ResourceUsage(cpuPercent: cpu, memoryGB: mem)
                        }
                    } else if trimmed.hasPrefix("ERROR:") {
                        let errorMsg = String(trimmed.dropFirst(6))
                        engineLog("Error: \(errorMsg)")
                        let resources = state.lastResources
                        Task { @MainActor in
                            progressHandler(state.lastProgress, "Error: \(errorMsg)", resources)
                        }
                    } else if trimmed.hasPrefix("WARNING:") {
                        engineLog("Warning: \(trimmed.dropFirst(8))")
                    } else if trimmed == "DONE" {
                        let resources = state.lastResources
                        Task { @MainActor in
                            progressHandler(1.0, "Complete", resources)
                        }
                    }
                }
            }
        }
        
        engineLog("About to call process.run()")
        try process.run()
        engineLog("process.run() returned, PID: \(process.processIdentifier)")
        
        // Wait for process to finish
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                engineLog("Process terminated with status: \(proc.terminationStatus)")
                outputHandle.readabilityHandler = nil
                
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                if proc.terminationStatus != 0 {
                    let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
                    engineLog("Process error: \(errStr)")
                    continuation.resume(throwing: SeparationError.pythonError("Process exited with code \(proc.terminationStatus): \(errStr)"))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

enum SeparationError: Error, LocalizedError {
    case pythonError(String)
    case modelNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .pythonError(let msg): return "Python error: \(msg)"
        case .modelNotFound(let name): return "Model not found: \(name)"
        }
    }
}

struct CancellationError: Error {}

extension StemCategory {
    var demucsSourceName: String {
        switch self {
        case .vocals, .leadVocal, .backingVocals, .vocalEffects, .noise: return "vocals"
        case .drums, .kick, .snare, .toms, .cymbals: return "drums"
        case .bass: return "bass"
        case .guitar, .acousticGuitar, .electricGuitar: return "guitar"
        case .piano, .otherInstruments: return "piano"
        case .other: return "other"
        }
    }
}