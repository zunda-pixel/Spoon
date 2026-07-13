public import Foundation

public enum SparseCheckoutError: LocalizedError, Sendable, Hashable {
  case emptyPaths

  public var errorDescription: String? {
    switch self {
    case .emptyPaths:
      "Sparse checkout requires at least one repository-relative path. Use Disable Sparse Checkout to restore the full working tree."
    }
  }
}

extension SystemGitClient {

  public func sparseCheckoutPaths() async throws -> [String]? {
    guard
      let enabled = try? await run(["config", "--bool", "core.sparseCheckout"]),
      enabled.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    else { return nil }
    let result = try await run(["sparse-checkout", "list"])
    return result.standardOutputText
      .split(separator: "\n")
      .map(String.init)
  }

  public func setSparseCheckout(paths: [String]) async throws {
    let normalized = paths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !normalized.isEmpty else { throw SparseCheckoutError.emptyPaths }
    try await runVoid(["sparse-checkout", "set", "--cone", "--"] + normalized)
  }

  public func disableSparseCheckout() async throws {
    try await runVoid(["sparse-checkout", "disable"])
  }
}
