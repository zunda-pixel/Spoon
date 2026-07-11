public import Foundation

/// An opened local repository. Identity is the canonical root path, which is
/// also the window value for `WindowGroup(for: Repository.ID.self)`.
public struct Repository: Sendable, Hashable, Identifiable, Codable {
  public var rootURL: URL

  public init(rootURL: URL) {
    // Canonicalize so `/path/to/repo` and `/path/to/repo/` (and other URL
    // spellings) produce one identity — id keys windows and caches.
    self.rootURL = URL(
      filePath: Self.canonicalPath(of: rootURL),
      directoryHint: .isDirectory
    )
  }

  public var id: String { Self.canonicalPath(of: rootURL) }

  private static func canonicalPath(of url: URL) -> String {
    var path = url.standardizedFileURL.path(percentEncoded: false)
    while path.count > 1, path.hasSuffix("/") {
      path.removeLast()
    }
    return path
  }

  public var name: String { rootURL.lastPathComponent }
}
