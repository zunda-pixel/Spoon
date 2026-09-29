import Foundation

extension SystemGitClient {
  public func submodules() async throws -> [Submodule] {
    // Most repositories have none; skip running git for them.
    let gitmodules = repositoryRoot.appending(path: ".gitmodules")
    guard FileManager.default.fileExists(atPath: gitmodules.path) else { return [] }
    let status = try await run(["submodule", "status"], timeout: .seconds(60))
    let modules = try? await run([
      "config", "--null", "--file", ".gitmodules", "--get-regexp", #"^submodule\..*\.(path|url)$"#,
    ])
    let byPath = SubmoduleParser.parseModules(modules?.standardOutputText ?? "")
    return SubmoduleParser.parseStatus(status.standardOutputText).map { submodule in
      var submodule = submodule
      submodule.name = byPath[submodule.path]?.name
      submodule.url = byPath[submodule.path]?.url
      return submodule
    }
  }

  public func updateSubmodules(paths: [String]) async throws {
    // Clones and fetches can take a while.
    try await runVoid(
      ["submodule", "update", "--init", "--recursive", "--"] + paths,
      timeout: .seconds(600)
    )
  }

  public func syncSubmodules(paths: [String]) async throws {
    try await runVoid(["submodule", "sync", "--recursive", "--"] + paths)
  }

  public func addSubmodule(url: String, path: String) async throws {
    try await runVoid(["submodule", "add", "--", url, path], timeout: .seconds(600))
  }

  public func deinitializeSubmodule(path: String, force: Bool) async throws {
    try await runVoid(["submodule", "deinit"] + (force ? ["--force"] : []) + ["--", path])
  }

  public func removeSubmodule(path: String, force: Bool) async throws {
    try await runVoid(["rm", "--quiet"] + (force ? ["--force"] : []) + ["--", path])
  }
}
