public import Foundation

public enum PullRequestURLBuilder {
  public static func createURL(
    for branch: Branch,
    remotes: [Remote],
    fallbackRepoRef: RepoRef?
  ) -> URL? {
    guard let repoRef = repoRef(for: branch, remotes: remotes) ?? fallbackRepoRef else {
      return nil
    }

    var components = URLComponents()
    components.scheme = "https"
    components.host = "github.com"
    components.path = "/\(repoRef.owner)/\(repoRef.name)/compare/\(branch.name)"
    components.queryItems = [URLQueryItem(name: "expand", value: "1")]
    return components.url
  }

  private static func repoRef(for branch: Branch, remotes: [Remote]) -> RepoRef? {
    guard let upstreamRemoteName = branch.upstreamRemoteName else { return nil }
    guard let remote = remotes.first(where: { $0.name == upstreamRemoteName }) else { return nil }
    return RemoteURLParser.gitHubRepo(from: remote.pushURL ?? remote.fetchURL)
  }
}
