import Foundation

extension RepositoryModel {
  /// One ignored path and the rule responsible.
  public struct IgnoredPath: Sendable, Hashable, Identifiable {
    public var path: String
    public var rule: IgnoreRule?

    public var id: String { path }
  }

  /// Ignored untracked paths with their rules, at most `limit` of them.
  public func ignoredPaths(limit: Int = 2_000) async throws -> (paths: [IgnoredPath], isTruncated: Bool) {
    let all = try await gitClient.ignoredPaths()
    let paths = Array(all.prefix(limit))
    let rules = try await gitClient.ignoreRules(for: paths)
    return (paths.map { IgnoredPath(path: $0, rule: rules[$0] ?? nil) }, all.count > limit)
  }

  /// Whether `path` is ignored, and by which line of which file.
  public func ignoreStatus(of path: String) async throws -> IgnoreStatus {
    if try await gitClient.isTracked(path: path) { return .tracked }
    guard let rule = try await gitClient.ignoreRules(for: [path]).values.first ?? nil else {
      return .notIgnored
    }
    return rule.reincludes ? .reincluded(rule) : .ignored(rule)
  }
}
