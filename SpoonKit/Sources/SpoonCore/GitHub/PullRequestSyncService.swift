import Foundation

/// Fetches all open PRs for a repository in one paginated GraphQL query —
/// never one call per branch — and joins them against local branches.
public actor PullRequestSyncService {
  private let client: GitHubAPIClient
  private let repoRef: RepoRef
  private let cacheTTL: Duration
  private var lastSync: (at: ContinuousClock.Instant, prs: [PullRequest])?
  private var pausedUntil: Date?

  public init(client: GitHubAPIClient, repoRef: RepoRef, cacheTTL: Duration = .seconds(60)) {
    self.client = client
    self.repoRef = repoRef
    self.cacheTTL = cacheTTL
  }

  static let query = """
    query($owner: String!, $name: String!, $after: String) {
      repository(owner: $owner, name: $name) {
        pullRequests(states: OPEN, first: 50, after: $after,
                     orderBy: {field: UPDATED_AT, direction: DESC}) {
          pageInfo { hasNextPage endCursor }
          nodes {
            number title url isDraft updatedAt
            headRefName baseRefName
            headRepositoryOwner { login }
            author { login }
            reviewDecision
            commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
          }
        }
      }
      rateLimit { remaining resetAt }
    }
    """

  // MARK: - Response decoding (mirrors the query shape)

  struct Response: Decodable, Sendable {
    struct Repo: Decodable, Sendable {
      var pullRequests: PRConnection
    }
    struct PRConnection: Decodable, Sendable {
      struct PageInfo: Decodable, Sendable {
        var hasNextPage: Bool
        var endCursor: String?
      }
      var pageInfo: PageInfo
      var nodes: [PRNode]
    }
    struct PRNode: Decodable, Sendable {
      struct Actor: Decodable, Sendable { var login: String }
      struct Commits: Decodable, Sendable {
        struct Node: Decodable, Sendable {
          struct CommitInfo: Decodable, Sendable {
            struct Rollup: Decodable, Sendable { var state: String }
            var statusCheckRollup: Rollup?
          }
          var commit: CommitInfo
        }
        var nodes: [Node]
      }
      var number: Int
      var title: String
      var url: String
      var isDraft: Bool
      var updatedAt: Date?
      var headRefName: String
      var baseRefName: String
      var headRepositoryOwner: Actor?
      var author: Actor?
      var reviewDecision: String?
      var commits: Commits
    }
    struct RateLimit: Decodable, Sendable {
      var remaining: Int
      var resetAt: Date?
    }
    var repository: Repo?
    var rateLimit: RateLimit?
  }

  /// Returns open PRs, respecting the TTL cache unless `force`.
  public func openPullRequests(force: Bool) async throws -> [PullRequest] {
    if let pausedUntil, pausedUntil > Date() {
      throw GitHubError(kind: .rateLimited(resetAt: pausedUntil))
    }
    if !force, let lastSync, ContinuousClock.now - lastSync.at < cacheTTL {
      return lastSync.prs
    }

    var results: [PullRequest] = []
    var cursor: String?
    var pages = 0
    repeat {
      let response = try await client.query(
        Self.query,
        variables: ["owner": repoRef.owner, "name": repoRef.name, "after": cursor],
        as: Response.self
      )
      if let rateLimit = response.rateLimit, rateLimit.remaining < 50 {
        pausedUntil = rateLimit.resetAt ?? Date().addingTimeInterval(300)
      }
      guard let connection = response.repository?.pullRequests else { break }
      results.append(contentsOf: connection.nodes.map(Self.pullRequest(from:)))
      cursor = connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : nil
      pages += 1
    } while cursor != nil && pages < 10  // 500 open PRs is plenty for badges

    lastSync = (ContinuousClock.now, results)
    return results
  }

  static func pullRequest(from node: Response.PRNode) -> PullRequest {
    PullRequest(
      number: node.number,
      title: node.title,
      url: node.url,
      isDraft: node.isDraft,
      headRefName: node.headRefName,
      headRepositoryOwner: node.headRepositoryOwner?.login,
      baseRefName: node.baseRefName,
      authorLogin: node.author?.login,
      reviewDecision: node.reviewDecision.flatMap(ReviewDecision.init(rawValue:)),
      checksState: node.commits.nodes.first?.commit.statusCheckRollup
        .flatMap { ChecksState(rawValue: $0.state) },
      updatedAt: node.updatedAt
    )
  }
}

/// Joins synced PRs to local branches — pure, and tolerant of forks.
public enum BranchPRLinker {
  /// A PR matches a local branch when the head ref equals the branch name
  /// AND the head owner is one we push to (any GitHub remote's owner).
  public static func link(
    branches: [Branch],
    pullRequests: [PullRequest],
    remoteOwners: Set<String>
  ) -> [String: PullRequest] {
    var byBranch: [String: PullRequest] = [:]
    for pr in pullRequests {
      guard let owner = pr.headRepositoryOwner, remoteOwners.contains(owner) else { continue }
      // Newest-updated PR wins if several share a head branch.
      if byBranch[pr.headRefName] == nil {
        byBranch[pr.headRefName] = pr
      }
    }
    return byBranch.filter { name, _ in branches.contains { $0.name == name } }
  }
}
