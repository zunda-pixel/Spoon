public import Foundation
public import MemberwiseInit

/// A local branch as reported by `git for-each-ref refs/heads`.
@MemberwiseInit(.public)
public struct Branch: Sendable, Hashable, Identifiable {
  /// Short name, e.g. `main` or `feature/login`.
  public var name: String
  public var isCurrent: Bool
  public var tip: ObjectID
  /// Subject line of the tip commit.
  public var subject: String
  /// Short upstream name, e.g. `origin/main`.
  public var upstream: String?
  /// Commits ahead of / behind upstream. `nil` when there is no upstream
  /// or the upstream is gone.
  public var ahead: Int?
  public var behind: Int?
  /// The configured upstream branch has been deleted on the remote.
  public var upstreamGone: Bool = false
  public var committedAt: Date?

  public var id: String { name }

  /// Remote-tracking prefix of `upstream` (`origin` for `origin/main`).
  public var upstreamRemoteName: String? {
    guard let upstream, let slash = upstream.firstIndex(of: "/") else { return nil }
    return String(upstream[..<slash])
  }
}
