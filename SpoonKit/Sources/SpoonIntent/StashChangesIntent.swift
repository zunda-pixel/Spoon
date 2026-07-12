public import AppIntents

import Defaults
import Foundation
import SpoonCore

/// Stashes the working-tree changes of a recent repository. Headless: it
/// builds its own git client, so it works even when Spoon is not running
/// (open windows pick up the change via the file watcher when it is).
public struct StashChangesIntent: AppIntent {
  static public let title: LocalizedStringResource = "Stash Changes"
  static public let description = IntentDescription(
    "Stashes the working-tree changes (including untracked files) of a recent git repository.")

  @Parameter(title: "Repository Name")
  public var repositoryName: String?

  @Parameter(title: "Stash Message")
  public var message: String?

  public init() {}

  public func perform() async throws -> some IntentResult & ProvidesDialog {
    let repository: Repository
    switch RecentRepositories.resolve(name: repositoryName, in: RecentRepositories.all()) {
    case .failure(let message):
      return .result(dialog: "\(message)")
    case .found(let match):
      repository = match
    }

    let runner = SubprocessCommandRunner()
    let locator = ToolLocator(runner: runner) { tool in
      Defaults[.toolPathOverrides][tool.rawValue]
    }
    guard let git = await locator.resolve(.git) else {
      return .result(dialog: "git was not found on this Mac.")
    }
    let client = SystemGitClient(repositoryRoot: repository.rootURL, git: git, runner: runner)
    let status = try await client.status()
    guard !status.isClean else {
      return .result(dialog: "\(repository.name) has no changes to stash.")
    }
    let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    try await client.saveStash(
      message: trimmedMessage.isEmpty ? nil : trimmedMessage,
      includeUntracked: true
    )
    return .result(dialog: "Stashed changes in \(repository.name).")
  }
}
