public import Foundation

/// Repository discovery, initialization, and cloning operations.
public enum GitRepositoryLifecycle {
  public static func repositoryRoot(
    containing url: URL,
    git: URL,
    runner: any CommandRunning
  ) async -> URL? {
    let command = GitCommand.make(
      git: git,
      repository: url,
      arguments: ["rev-parse", "--show-toplevel"],
      timeout: .seconds(10)
    )
    guard let result = try? await runner.run(command), result.isSuccess else { return nil }
    let path = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else { return nil }
    return URL(filePath: path)
  }

  public static func initialize(
    at destination: URL,
    initialBranch: String,
    git: URL,
    runner: any CommandRunning
  ) async throws {
    let command = GitCommand.make(
      git: git,
      repository: nil,
      arguments: ["init", "--initial-branch", initialBranch, destination.path],
      timeout: .seconds(30)
    )
    _ = try await runner.run(command).checkSuccess(of: command)
  }

  public static func clone(
    from remoteURL: String,
    to destination: URL,
    options: CloneOptions = .standard,
    git: URL,
    runner: any CommandRunning,
    progress: @escaping @Sendable (String) -> Void
  ) async throws {
    let command = GitCommand.make(
      git: git,
      repository: nil,
      arguments: options.cloneArguments() + [remoteURL, destination.path],
      timeout: .seconds(3600)
    )
    var standardError = Data()
    for try await event in runner.events(command) {
      switch event {
      case .standardError(let chunk):
        standardError.append(chunk)
        let text = String(decoding: chunk, as: UTF8.self)
        let lines = text.split(whereSeparator: { $0 == "\r" || $0 == "\n" })
        if let last = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
          progress(String(last))
        }
      case .standardOutput:
        break
      case .exited(let code):
        guard code == 0 else {
          throw CommandError(
            kind: .nonZeroExit,
            command: command,
            exitCode: code,
            standardErrorExcerpt: CommandError.excerpt(from: standardError)
          )
        }
      }
    }
  }
}
