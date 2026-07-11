import Foundation
import Valet

/// Source of the GitHub API token. Chained: `gh` CLI first (its keyring
/// stays the source of truth; token held in memory only), manual PAT from
/// the app's Keychain as fallback.
public protocol GitHubTokenProvider: Sendable {
  func token() async -> String?
}

/// Reuses the user's `gh auth token`. Cached in memory for the session;
/// never persisted by Spoon.
public actor GhCLITokenProvider: GitHubTokenProvider {
  private let runner: any CommandRunning
  private let toolLocator: ToolLocator
  private var cached: String?
  private var probed = false

  public init(runner: any CommandRunning, toolLocator: ToolLocator) {
    self.runner = runner
    self.toolLocator = toolLocator
  }

  public func token() async -> String? {
    if probed { return cached }
    probed = true
    guard let gh = await toolLocator.resolve(.gh) else { return nil }
    let command = Command(
      executable: gh,
      arguments: ["auth", "token"],
      timeout: .seconds(10)
    )
    guard let result = try? await runner.run(command), result.isSuccess else { return nil }
    let token = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
    cached = token.isEmpty ? nil : token
    return cached
  }

  /// Called on 401 so an externally refreshed `gh` login is picked up.
  public func invalidate() {
    probed = false
    cached = nil
  }
}

/// Manual PAT stored in the app's Keychain via Valet (Settings → GitHub).
public struct KeychainTokenProvider: GitHubTokenProvider {
  static let valetIdentifier = "SpoonGitHub"
  static let tokenKey = "github-pat"

  public init() {}

  public func token() async -> String? {
    guard let stored = try? Self.valet()?.string(forKey: Self.tokenKey), !stored.isEmpty else {
      return nil
    }
    return stored
  }

  public static func save(token: String) throws {
    guard let valet = valet() else { return }
    if token.isEmpty {
      try valet.removeObject(forKey: tokenKey)
    } else {
      try valet.setString(token, forKey: tokenKey)
    }
  }

  public static func storedToken() -> String? {
    try? valet()?.string(forKey: tokenKey)
  }

  private static func valet() -> Valet? {
    guard let identifier = Identifier(nonEmpty: valetIdentifier) else { return nil }
    return Valet.valet(with: identifier, accessibility: .whenUnlocked)
  }
}

public struct ChainedTokenProvider: GitHubTokenProvider {
  private let providers: [any GitHubTokenProvider]

  public init(_ providers: [any GitHubTokenProvider]) {
    self.providers = providers
  }

  public func token() async -> String? {
    for provider in providers {
      if let token = await provider.token() {
        return token
      }
    }
    return nil
  }
}
