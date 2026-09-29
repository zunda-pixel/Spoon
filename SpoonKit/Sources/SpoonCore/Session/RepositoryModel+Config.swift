import Foundation

extension RepositoryModel {
  public func repositoryConfig() async throws -> RepositoryConfig {
    try await gitClient.repositoryConfig()
  }

  /// Writes `changes` to this repository's `.git/config`; a `nil` value
  /// removes the local setting so the inherited one applies.
  @discardableResult
  public func saveRepositoryConfig(_ changes: [RepositorySetting: String?]) async -> Bool {
    defer { configGeneration += 1 }
    return await perform { client in
      // Sorted so the writes happen in a predictable order.
      for setting in changes.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
        try await client.setRepositoryConfig(setting, to: changes[setting] ?? nil)
      }
    }
  }
}
