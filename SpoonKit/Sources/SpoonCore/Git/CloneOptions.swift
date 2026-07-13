import Foundation

/// Options passed to `git clone` when creating a new local copy.
public struct CloneOptions: Sendable, Equatable {
  /// Omit blob contents until they are needed (`--filter=blob:none`).
  public var filterBlobNone: Bool
  /// Shallow clone depth (`--depth`); `nil` when not shallow.
  public var depth: Int?
  /// Fetch and check out only one branch (`--single-branch`).
  public var singleBranch: Bool
  /// Branch to check out (`--branch`); the remote's default when `nil`.
  public var branch: String?

  public static let standard = CloneOptions()

  public init(
    filterBlobNone: Bool = false,
    depth: Int? = nil,
    singleBranch: Bool = false,
    branch: String? = nil
  ) {
    self.filterBlobNone = filterBlobNone
    self.depth = depth
    self.singleBranch = singleBranch
    let trimmed = branch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.branch = trimmed.isEmpty ? nil : trimmed
  }

  /// `git clone` arguments before the remote URL and destination path.
  func cloneArguments() -> [String] {
    var arguments = ["clone", "--progress"]
    if filterBlobNone {
      arguments.append("--filter=blob:none")
    }
    if let depth, depth > 0 {
      arguments.append("--depth=\(depth)")
    }
    if singleBranch {
      arguments.append("--single-branch")
    }
    if let branch {
      arguments.append("--branch")
      arguments.append(branch)
    }
    return arguments
  }
}
