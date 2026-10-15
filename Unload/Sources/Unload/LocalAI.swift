import Foundation

/// Models currently loaded by local AI servers. Unloading frees their memory without quitting the server.
struct LoadedModel: Identifiable, Hashable {
    enum Source: String { case ollama = "Ollama", lmStudio = "LM Studio" }

    let name: String
    let size: UInt64
    let source: Source

    var id: String { "\(source.rawValue):\(name)" }
}

enum LocalAI {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 3
        return URLSession(configuration: configuration)
    }()

    // MARK: Ollama (http://127.0.0.1:11434)

    private struct OllamaPS: Decodable {
        struct Model: Decodable {
            let name: String
            let size: UInt64?
            let size_vram: UInt64?
        }
        let models: [Model]?
    }

    static func ollamaModels() async -> [LoadedModel] {
        guard let url = URL(string: "http://127.0.0.1:11434/api/ps"),
              let (data, _) = try? await session.data(from: url),
              let response = try? JSONDecoder().decode(OllamaPS.self, from: data) else { return [] }
        return (response.models ?? []).map {
            LoadedModel(name: $0.name, size: max($0.size ?? 0, $0.size_vram ?? 0), source: .ollama)
        }
    }

    /// keep_alive 0 tells Ollama to evict the model right away.
    static func unloadOllama(_ model: String) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "keep_alive": 0])
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: LM Studio (http://127.0.0.1:1234, CLI ~/.lmstudio/bin/lms)

    private struct LMStudioModels: Decodable {
        struct Model: Decodable {
            let id: String
            let state: String?
        }
        let data: [Model]?
    }

    static func lmStudioModels() async -> [LoadedModel] {
        guard let url = URL(string: "http://127.0.0.1:1234/api/v0/models"),
              let (data, _) = try? await session.data(from: url),
              let response = try? JSONDecoder().decode(LMStudioModels.self, from: data) else { return [] }
        return (response.data ?? [])
            .filter { $0.state == "loaded" }
            .map { LoadedModel(name: $0.id, size: 0, source: .lmStudio) }
    }

    static var lmsPath: String? {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".lmstudio/bin/lms")
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    static func unloadLMStudio(_ model: String?) async -> Bool {
        guard let lms = lmsPath else { return false }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: lms)
            process.arguments = model.map { ["unload", $0] } ?? ["unload", "--all"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    static func loadedModels() async -> [LoadedModel] {
        async let ollama = ollamaModels()
        async let lmStudio = lmStudioModels()
        return await ollama + lmStudio
    }

    static func unload(_ model: LoadedModel) async -> Bool {
        switch model.source {
        case .ollama: return await unloadOllama(model.name)
        case .lmStudio: return await unloadLMStudio(model.name)
        }
    }
}
