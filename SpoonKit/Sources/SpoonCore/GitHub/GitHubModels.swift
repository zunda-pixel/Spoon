public import Foundation
public import MemberwiseInit

/// `owner/name` identity of a GitHub repository.
@MemberwiseInit(.public)
public struct RepoRef: Sendable, Hashable, Codable {
  public var owner: String
  public var name: String

  public var slug: String { "\(owner)/\(name)" }
}

public enum ReviewDecision: String, Sendable, Codable {
  case approved = "APPROVED"
  case changesRequested = "CHANGES_REQUESTED"
  case reviewRequired = "REVIEW_REQUIRED"
}

/// `statusCheckRollup.state` — the combined CI verdict for a commit.
public enum ChecksState: String, Sendable, Codable {
  case success = "SUCCESS"
  case failure = "FAILURE"
  case error = "ERROR"
  case pending = "PENDING"
  case expected = "EXPECTED"

  public var isRunning: Bool { self == .pending || self == .expected }
  public var isFailure: Bool { self == .failure || self == .error }
}

/// An open pull request, as synced from GitHub.
@MemberwiseInit(.public)
public struct PullRequest: Sendable, Hashable, Codable, Identifiable {
  public var number: Int
  public var title: String
  public var url: String
  public var isDraft: Bool = false
  /// Branch name on the head repository.
  public var headRefName: String
  /// Owner login of the head repository (differs from base for forks).
  public var headRepositoryOwner: String? = nil
  public var baseRefName: String
  public var authorLogin: String? = nil
  public var reviewDecision: ReviewDecision? = nil
  public var checksState: ChecksState? = nil
  public var updatedAt: Date? = nil

  public var id: Int { number }
}

/// Sync status surfaced to the UI. GitHub being unreachable must never
/// degrade the local git experience.
public enum PRSyncState: Sendable, Hashable {
  case idle
  case syncing
  case synced(Date)
  /// No GitHub remote — PR features hidden entirely.
  case noGitHubRemote
  /// No usable token; Settings explains how to sign in.
  case unauthenticated
  /// API said back off until the given time.
  case rateLimited(until: Date?)
  case failed(String)
}
