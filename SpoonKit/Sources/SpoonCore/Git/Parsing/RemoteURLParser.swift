import Foundation

/// Extracts `(owner, repo)` from GitHub remote URLs. Non-GitHub remotes
/// yield nil — PR features silently disable for them.
public enum RemoteURLParser {
  /// Handles the three spellings git produces:
  /// - `git@github.com:owner/repo.git`
  /// - `https://github.com/owner/repo(.git)`
  /// - `ssh://git@github.com/owner/repo(.git)`
  public static func gitHubRepo(from remoteURL: String) -> RepoRef? {
    var rest: Substring

    if let scpRange = remoteURL.range(of: "@github.com:") {
      rest = remoteURL[scpRange.upperBound...]
    } else if let httpsRange = remoteURL.range(of: "://github.com/") {
      rest = remoteURL[httpsRange.upperBound...]
    } else if let sshRange = remoteURL.range(of: "@github.com/") {
      rest = remoteURL[sshRange.upperBound...]
    } else {
      return nil
    }

    if rest.hasSuffix(".git") {
      rest = rest.dropLast(4)
    }
    while rest.hasSuffix("/") {
      rest = rest.dropLast()
    }

    let parts = rest.split(separator: "/")
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
    return RepoRef(owner: String(parts[0]), name: String(parts[1]))
  }
}
