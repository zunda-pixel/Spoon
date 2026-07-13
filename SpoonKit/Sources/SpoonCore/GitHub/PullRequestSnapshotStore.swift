import CryptoKit
public import Foundation

/// Persists the last PR sync per repository so cold starts show
/// stale-but-instant badges while the first network sync runs.
public struct PullRequestSnapshotStore: Sendable {
  public struct Snapshot: Sendable, Codable {
    public var savedAt: Date
    public var pullRequests: [PullRequest]
  }

  private let directory: URL

  public init(directory: URL? = nil) {
    self.directory =
      directory
      ?? URL.applicationSupportDirectory
      .appending(path: "Spoon/pr-cache", directoryHint: .isDirectory)
  }

  public func load(repositoryID: String) -> Snapshot? {
    guard let data = try? Data(contentsOf: fileURL(for: repositoryID)) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(Snapshot.self, from: data)
  }

  public func save(_ pullRequests: [PullRequest], repositoryID: String, at date: Date = Date()) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(Snapshot(savedAt: date, pullRequests: pullRequests))
    else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? data.write(to: fileURL(for: repositoryID), options: .atomic)
  }

  private func fileURL(for repositoryID: String) -> URL {
    let digest = SHA256.hash(data: Data(repositoryID.utf8))
    let name = digest.map { byte in
      let hex = String(byte, radix: 16)
      return byte < 16 ? "0" + hex : hex
    }.joined().prefix(32)
    return directory.appending(path: "\(name).json")
  }
}
