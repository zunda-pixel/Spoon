import Foundation

extension RepositoryModel {
  public func storage() async throws -> RepositoryStorage {
    try await gitClient.storage()
  }

  @discardableResult
  public func optimize(aggressive: Bool) async -> Bool {
    await perform { try await $0.optimize(aggressive: aggressive) }
  }

  public func isBackgroundMaintenanceEnabled() async -> Bool {
    (try? await gitClient.isBackgroundMaintenanceEnabled()) ?? false
  }

  @discardableResult
  public func setBackgroundMaintenance(_ enabled: Bool) async -> Bool {
    await perform { try await $0.setBackgroundMaintenance(enabled) }
  }
}
