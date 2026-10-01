import Foundation

extension SystemGitClient {
  public func storage() async throws -> RepositoryStorage {
    RepositoryStorage.parse(try await run(["count-objects", "-v"]).standardOutputText)
  }

  public func optimize(aggressive: Bool) async throws {
    // Large repositories take a while; an aggressive run far longer.
    try await runVoid(
      ["gc", "--quiet"] + (aggressive ? ["--aggressive"] : []), timeout: .seconds(3 * 3600))
  }

  public func isBackgroundMaintenanceEnabled() async throws -> Bool {
    let command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: ["config", "--global", "--get-all", "maintenance.repo"],
      timeout: .seconds(10)
    )
    let result = try await runner.run(command)
    // Exit 1: no repository is registered.
    if result.exitCode == 1 { return false }
    let registered = try result.checkSuccess(of: command).standardOutputText
      .split(whereSeparator: \.isNewline).map { Self.canonicalPath(String($0)) }
    return registered.contains(Self.canonicalPath(repositoryRoot.path(percentEncoded: false)))
  }

  public func setBackgroundMaintenance(_ enabled: Bool) async throws {
    try await runVoid(["maintenance", enabled ? "start" : "unregister"], timeout: .seconds(60))
  }

  /// Registered paths are git's real path; compare without symlinks or a
  /// trailing slash.
  private static func canonicalPath(_ path: String) -> String {
    let resolved = URL(filePath: path).resolvingSymlinksInPath().path(percentEncoded: false)
    return resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
  }
}
