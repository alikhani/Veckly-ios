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

        self.fileURL = Self.rootDirectory(fileManager: fileManager, baseDirectory: baseDirectory)
            .appendingPathComponent(fileName)
    }

    /// `<Caches>/Veckly` — the one folder every cache file lives under.
    private static func rootDirectory(fileManager: FileManager, baseDirectory: URL?) -> URL {
        let cacheDirectory = baseDirectory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return cacheDirectory.appendingPathComponent("Veckly", isDirectory: true)
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
        try? fileManager.removeItem(
            at: rootDirectory(fileManager: fileManager, baseDirectory: baseDirectory)
                .appendingPathComponent(folder, isDirectory: true)
        )
    }

    /// Removes every cache file the app has written, for every household and
    /// week. Callers can't list them (prep batches are cached per household and
    /// week), so sign-out and account deletion wipe the whole folder instead of
    /// asking each store to delete what it remembers. Anything stored outside
    /// `<Caches>/Veckly` is untouched.
    static func deleteAll(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        try? fileManager.removeItem(at: rootDirectory(fileManager: fileManager, baseDirectory: baseDirectory))
    }
}
