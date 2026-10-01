import Foundation
import Retry
import Testing

@testable import SpoonCore

@Suite("RemoteURLParser")
struct RemoteURLParserTests {
  @Test(arguments: [
    ("git@github.com:owner/repo.git", "owner", "repo"),
    ("https://github.com/owner/repo.git", "owner", "repo"),
    ("https://github.com/owner/repo", "owner", "repo"),
    ("ssh://git@github.com/owner/repo.git", "owner", "repo"),
    ("https://github.com/owner/repo/", "owner", "repo"),
    ("git@github.com:my-org/my.repo.name.git", "my-org", "my.repo.name"),
  ])
  func parsesGitHubRemotes(url: String, owner: String, name: String) {
    let ref = RemoteURLParser.gitHubRepo(from: url)
    #expect(ref == RepoRef(owner: owner, name: name))
  }

  @Test(arguments: [
    "https://gitlab.com/owner/repo.git",
    "git@bitbucket.org:owner/repo.git",
    "https://github.com/owner",
    "not a url",
    "",
  ])
  func rejectsNonGitHubOrMalformed(url: String) {
    #expect(RemoteURLParser.gitHubRepo(from: url) == nil)
  }
}

@Suite("PullRequestURLBuilder")
struct PullRequestURLBuilderTests {
  private let oid = ObjectID(rawValue: String(repeating: "a", count: 40))!

  @Test func createsCompareURLForFallbackGitHubRepo() throws {
    let url = PullRequestURLBuilder.createURL(
      for: branch("feature/new-ui"),
      remotes: [],
      fallbackRepoRef: RepoRef(owner: "owner", name: "repo")
    )

    #expect(url?.absoluteString == "https://github.com/owner/repo/compare/feature/new-ui?expand=1")
  }

  @Test func usesUpstreamGitHubRemoteBeforeFallback() throws {
    let url = PullRequestURLBuilder.createURL(
      for: branch("topic", upstream: "fork/topic"),
      remotes: [
        Remote(name: "origin", fetchURL: "https://github.com/base/repo.git"),
        Remote(name: "fork", fetchURL: "git@github.com:me/repo.git"),
      ],
      fallbackRepoRef: RepoRef(owner: "base", name: "repo")
    )

    #expect(url?.absoluteString == "https://github.com/me/repo/compare/topic?expand=1")
  }

  @Test func returnsNilWithoutGitHubRepo() throws {
    let url = PullRequestURLBuilder.createURL(
      for: branch("topic"),
      remotes: [Remote(name: "origin", fetchURL: "https://gitlab.com/owner/repo.git")],
      fallbackRepoRef: nil
    )

    #expect(url == nil)
  }

  private func branch(_ name: String, upstream: String? = nil) -> Branch {
    Branch(
      name: name,
      isCurrent: false,
      tip: oid,
      subject: "",
      upstream: upstream,
      ahead: nil,
      behind: nil,
      committedAt: nil
    )
  }
}

@Suite("PullRequestSync")
struct PullRequestSyncTests {
  /// Recorded GraphQL response fixture — the decode contract with GitHub.
  private let fixture = """
    {
      "data": {
        "repository": {
          "pullRequests": {
            "pageInfo": { "hasNextPage": false, "endCursor": "abc" },
            "nodes": [
              {
                "number": 42,
                "title": "feat: add history view",
                "url": "https://github.com/o/r/pull/42",
                "isDraft": false,
                "updatedAt": "2026-07-10T12:34:56Z",
                "headRefName": "feature/history",
                "baseRefName": "main",
                "headRepositoryOwner": { "login": "o" },
                "author": { "login": "zunda" },
                "reviewDecision": "APPROVED",
                "commits": { "nodes": [ { "commit": { "statusCheckRollup": { "state": "SUCCESS" } } } ] }
              },
              {
                "number": 43,
                "title": "wip",
                "url": "https://github.com/o/r/pull/43",
                "isDraft": true,
                "updatedAt": null,
                "headRefName": "fork-branch",
                "baseRefName": "main",
                "headRepositoryOwner": { "login": "someone-else" },
                "author": null,
                "reviewDecision": null,
                "commits": { "nodes": [ { "commit": { "statusCheckRollup": null } } ] }
              }
            ]
          }
        },
        "rateLimit": { "remaining": 4999, "resetAt": "2026-07-11T15:00:00Z" }
      }
    }
    """

  struct StubTransport: GitHubTransport {
    var body: String
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (
      status: Int, body: Data
    ) {
      (200, Data(self.body.utf8))
    }
  }

  struct StubToken: GitHubTokenProvider {
    var value: String?
    func token() async -> String? { value }
  }

  /// Answers with each status in turn, then with 200 and `body`.
  actor FlakyTransport: GitHubTransport {
    private var statuses: [Int]
    private let body: String
    private(set) var calls = 0

    init(statuses: [Int], body: String) {
      self.statuses = statuses
      self.body = body
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (
      status: Int, body: Data
    ) {
      calls += 1
      let status = statuses.isEmpty ? 200 : statuses.removeFirst()
      return (status, Data(self.body.utf8))
    }
  }

  private func makeService(transport: any GitHubTransport, token: String? = "tok")
    -> PullRequestSyncService
  {
    PullRequestSyncService(
      client: GitHubAPIClient(
        tokenProvider: StubToken(value: token), transport: transport, retryBackoff: .constant(.zero)),
      repoRef: RepoRef(owner: "o", name: "r")
    )
  }

  @Test func decodesPRsFromGraphQLFixture() async throws {
    let service = makeService(transport: StubTransport(body: fixture))
    let prs = try await service.openPullRequests(force: true)
    #expect(prs.count == 2)

    let first = prs[0]
    #expect(first.number == 42)
    #expect(first.headRefName == "feature/history")
    #expect(first.headRepositoryOwner == "o")
    #expect(first.reviewDecision == .approved)
    #expect(first.checksState == .success)
    #expect(first.updatedAt != nil)

    let second = prs[1]
    #expect(second.isDraft)
    #expect(second.reviewDecision == nil)
    #expect(second.checksState == nil)
  }

  @Test func missingTokenThrowsUnauthenticated() async {
    let service = makeService(transport: StubTransport(body: fixture), token: nil)
    await #expect(throws: GitHubError.self) {
      try await service.openPullRequests(force: true)
    }
  }

  @Test func graphQLErrorSurfaces() async {
    let service = makeService(
      transport: StubTransport(body: #"{"data": null, "errors": [{"message": "Bad credentials"}]}"#)
    )
    await #expect(throws: GitHubError.self) {
      try await service.openPullRequests(force: true)
    }
  }
}

extension PullRequestSyncTests {
  @Test func serverErrorsAreRetried() async throws {
    let transport = FlakyTransport(statuses: [502, 503], body: fixture)
    let prs = try await makeService(transport: transport).openPullRequests(force: true)
    #expect(prs.count == 2)
    #expect(await transport.calls == 3)
  }

  @Test func retriesStopAfterThreeAttempts() async {
    let transport = FlakyTransport(statuses: [500, 500, 500, 500], body: fixture)
    let error = await #expect(throws: GitHubError.self) {
      try await makeService(transport: transport).openPullRequests(force: true)
    }
    #expect(error?.kind == .http(status: 500))
    #expect(await transport.calls == 3)
  }

  @Test func signInAndRateLimitFailuresAreNotRetried() async {
    for status in [401, 403, 429] {
      let transport = FlakyTransport(statuses: [status], body: fixture)
      await #expect(throws: GitHubError.self) {
        try await makeService(transport: transport).openPullRequests(force: true)
      }
      #expect(await transport.calls == 1)
    }
  }

  @Test func onlyTransientFailuresCountAsTransient() {
    #expect(NetworkRetry.isTransient(URLError(.timedOut)))
    #expect(NetworkRetry.isTransient(URLError(.networkConnectionLost)))
    #expect(!NetworkRetry.isTransient(URLError(.cancelled)))
    #expect(!NetworkRetry.isTransient(URLError(.userAuthenticationRequired)))
    #expect(NetworkRetry.isTransient(GitHubReleaseFeed.FeedError.unexpectedStatus(503)))
    #expect(!NetworkRetry.isTransient(GitHubReleaseFeed.FeedError.unexpectedStatus(404)))
    #expect(!NetworkRetry.isTransient(GitHubError(kind: .http(status: 501))))
    #expect(!NetworkRetry.isTransient(GitHubError(kind: .decoding)))
  }
}

@Suite("BranchPRLinker")
struct BranchPRLinkerTests {
  private func branch(_ name: String) -> Branch {
    Branch(
      name: name,
      isCurrent: false,
      tip: ObjectID(rawValue: String(repeating: "a", count: 40))!,
      subject: "",
      upstream: nil,
      ahead: nil,
      behind: nil,
      committedAt: nil
    )
  }

  private func pr(_ number: Int, head: String, owner: String?) -> PullRequest {
    PullRequest(
      number: number,
      title: "PR \(number)",
      url: "",
      headRefName: head,
      headRepositoryOwner: owner,
      baseRefName: "main"
    )
  }

  @Test func linksMatchingBranchAndOwner() {
    let links = BranchPRLinker.link(
      branches: [branch("feature/x"), branch("main")],
      pullRequests: [pr(1, head: "feature/x", owner: "me")],
      remoteOwners: ["me"]
    )
    #expect(links["feature/x"]?.number == 1)
    #expect(links["main"] == nil)
  }

  @Test func ignoresForkPRsFromUnknownOwners() {
    let links = BranchPRLinker.link(
      branches: [branch("feature/x")],
      pullRequests: [pr(1, head: "feature/x", owner: "stranger")],
      remoteOwners: ["me"]
    )
    #expect(links.isEmpty)
  }

  @Test func ignoresPRsWithoutLocalBranch() {
    let links = BranchPRLinker.link(
      branches: [branch("main")],
      pullRequests: [pr(1, head: "gone-branch", owner: "me")],
      remoteOwners: ["me"]
    )
    #expect(links.isEmpty)
  }
}
