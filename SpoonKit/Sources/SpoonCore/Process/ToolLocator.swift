public import Foundation

/// External CLI tools Spoon depends on.
public enum ExternalTool: String, Sendable, CaseIterable, Codable {
  case git
  case gh
  case claude
  case codex
}

/// Resolves external tools to absolute paths.
///
/// GUI apps launched from Finder inherit only `/usr/bin:/bin:/usr/sbin:/sbin`,
/// so `which` semantics don't apply. Resolution order:
/// 1. user override (Settings)
/// 2. fixed candidate locations, checked for executability
/// 3. a one-shot non-interactive login-shell probe (`$SHELL -l -c 'command -v …'`)
public actor ToolLocator {
  private let runner: any CommandRunning
  private let override: @Sendable (ExternalTool) -> String?
  private var cache: [ExternalTool: URL] = [:]
  private var probedLoginShell = false

  public init(
    runner: any CommandRunning,
    override: @escaping @Sendable (ExternalTool) -> String? = { _ in nil }
  ) {
    self.runner = runner
    self.override = override
  }

  public func resolve(_ tool: ExternalTool) async -> URL? {
    if let overridePath = override(tool) {
      let url = URL(filePath: overridePath)
      return isExecutable(url) ? url : nil
    }
    if let cached = cache[tool] { return cached }

    if let found = Self.candidates(for: tool).first(where: isExecutable) {
      cache[tool] = found
      return found
    }

    if let probed = await loginShellProbe(tool) {
      cache[tool] = probed
      return probed
    }
    return nil
  }

  /// Drops cached results so Settings changes and new installs are picked up.
  public func invalidate() {
    cache.removeAll()
    probedLoginShell = false
  }

  // MARK: - Candidates

  private static func candidates(for tool: ExternalTool) -> [URL] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    switch tool {
    case .git:
      // Prefer the Xcode/CLT shim: always present on a dev machine and
      // avoids Homebrew-version surprises.
      return [
        URL(filePath: "/usr/bin/git"),
        URL(filePath: "/opt/homebrew/bin/git"),
        URL(filePath: "/usr/local/bin/git"),
      ]
    case .gh:
      return [
        URL(filePath: "/opt/homebrew/bin/gh"),
        URL(filePath: "/usr/local/bin/gh"),
        home.appending(path: ".local/bin/gh"),
      ]
    case .claude:
      return [
        home.appending(path: ".local/bin/claude"),
        URL(filePath: "/opt/homebrew/bin/claude"),
        URL(filePath: "/usr/local/bin/claude"),
        home.appending(path: ".claude/local/claude"),
        home.appending(path: ".bun/bin/claude"),
        home.appending(path: "Library/pnpm/claude"),
        home.appending(path: ".volta/bin/claude"),
      ]
    case .codex:
      return [
        URL(filePath: "/opt/homebrew/bin/codex"),
        URL(filePath: "/usr/local/bin/codex"),
        home.appending(path: ".local/bin/codex"),
        home.appending(path: ".cargo/bin/codex"),
      ]
    }
  }

  private nonisolated func isExecutable(_ url: URL) -> Bool {
    FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false))
  }

  // MARK: - Login-shell probe

  private func loginShellProbe(_ tool: ExternalTool) async -> URL? {
    // Probe at most once per cache generation; a missing tool stays missing
    // until `invalidate()`.
    guard !probedLoginShell else { return nil }
    probedLoginShell = true

    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let names = ExternalTool.allCases.map(\.rawValue).joined(separator: " ")
    // Never `-i`: interactive rc files hang GUI-spawned shells.
    let command = Command(
      executable: URL(filePath: shell),
      arguments: ["-l", "-c", "command -v \(names)"],
      timeout: .seconds(5)
    )
    guard let result = try? await runner.run(command) else { return nil }

    // `command -v a b c` prints one path per found tool; missing tools are
    // simply absent (and exit is non-zero, which we ignore).
    for line in result.standardOutputText.split(separator: "\n") {
      let path = String(line)
      guard path.hasPrefix("/") else { continue }
      let url = URL(filePath: path)
      guard let name = ExternalTool(rawValue: url.lastPathComponent) else { continue }
      if cache[name] == nil, isExecutable(url) {
        cache[name] = url
      }
    }
    return cache[tool]
  }
}
