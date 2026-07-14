import Foundation

extension SystemGitClient {

  public func branches() async throws -> [Branch] {
    let result = try await run([
      "for-each-ref", "refs/heads",
      "--sort=-committerdate",
      "--format=\(GitRefParser.branchFormat)",
    ])
    return try GitRefParser.parseBranches(result.standardOutput)
  }

  public func switchBranch(_ branch: String) async throws {
    try await runVoid(["switch", branch])
  }

  public func switchToRevision(_ oid: ObjectID) async throws {
    try await runVoid(["switch", "--detach", oid.rawValue])
  }

  public func merge(branch: String, options: MergeOptions) async throws {
    try await runVoid(options.arguments(branch: branch), timeout: .seconds(120))
  }

  public func createBranch(
    name: String,
    from startPoint: String?,
    switchToBranch: Bool
  ) async throws {
    var arguments = switchToBranch ? ["switch", "-c", name] : ["branch", name]
    if let startPoint {
      arguments.append(startPoint)
    }
    try await runVoid(arguments)
  }

  public func switchToRemoteBranch(_ remoteBranch: String) async throws {
    try await runVoid(["switch", "--track", remoteBranch])
  }

  public func deleteBranch(name: String, force: Bool) async throws {
    try await runVoid(["branch", force ? "-D" : "-d", name])
  }

  public func renameBranch(from oldName: String, to newName: String) async throws {
    try await runVoid(["branch", "-m", oldName, newName])
  }

  public func defaultBranch() async throws -> String {
    if let result = try? await run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]) {
      let name = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
      if let slash = name.firstIndex(of: "/") {
        return String(name[name.index(after: slash)...])
      }
    }
    let branches = try await branches()
    if branches.contains(where: { $0.name == "main" }) { return "main" }
    if branches.contains(where: { $0.name == "master" }) { return "master" }
    return branches.first(where: \.isCurrent)?.name ?? "HEAD"
  }
}
