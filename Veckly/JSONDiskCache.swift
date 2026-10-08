import Foundation

struct JSONDiskCache<Value: Codable> {
    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileName: String,
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.fileManager = fileManager

        let cacheDirectory = baseDirectory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.fileURL = cacheDirectory
            .appendingPathComponent("Veckly", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        let directory = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func delete() {
        try? fileManager.removeItem(at: fileURL)
    }

    /// Removes a whole sub-folder of cache files (those created with a
    /// `fileName` of `"<folder>/<name>.json"`) — for caches that hold one file
    /// per household and must be cleared together, e.g. on sign-out.
    static func deleteFolder(
        _ folder: String,
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        guard !folder.isEmpty, !folder.contains("/") else { return }
        let cacheDirectory = baseDirectory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        try? fileManager.removeItem(
            at: cacheDirectory
                .appendingPathComponent("Veckly", isDirectory: true)
                .appendingPathComponent(folder, isDirectory: true)
        )
    }
}
