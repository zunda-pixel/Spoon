public import Foundation

/// Where Spoon looks for its newest release.
public protocol ReleaseFeed: Sendable {
  func latestRelease() async throws -> AppRelease
  /// Downloads a release archive and returns its local file URL.
  func downloadArchive(of release: AppRelease) async throws -> URL
}

/// The public GitHub Releases API. Unauthenticated requests are enough for
/// one check per launch.
public struct GitHubReleaseFeed: ReleaseFeed {
  public var owner: String
  public var repository: String

  public init(owner: String = "zunda-pixel", repository: String = "Spoon") {
    self.owner = owner
    self.repository = repository
  }

  public enum FeedError: LocalizedError, Sendable, Hashable {
    case unexpectedStatus(Int)

    public var errorDescription: String? {
      switch self {
      case .unexpectedStatus(let status):
        "GitHub returned HTTP \(status) while checking for updates."
      }
    }
  }

  public func latestRelease() async throws -> AppRelease {
    let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    request.timeoutInterval = 30
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw FeedError.unexpectedStatus(status) }
    return try AppRelease.decodeLatest(from: data)
  }

  public func downloadArchive(of release: AppRelease) async throws -> URL {
    let (location, response) = try await URLSession.shared.download(from: release.archiveURL)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw FeedError.unexpectedStatus(status) }
    // The session deletes its temporary file once this call returns.
    let destination = FileManager.default.temporaryDirectory
      .appending(path: "spoon-update-\(UUID().uuidString).zip")
    try FileManager.default.moveItem(at: location, to: destination)
    return destination
  }
}
