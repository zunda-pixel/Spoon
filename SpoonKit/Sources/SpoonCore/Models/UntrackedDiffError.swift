public import Foundation

/// Why an untracked path has no diff to show.
public enum UntrackedDiffError: LocalizedError, Sendable, Hashable {
  case nestedRepository(path: String)

  public var errorDescription: String? {
    switch self {
    case .nestedRepository(let path):
      "“\(path)” is a folder with its own Git repository. Add it as a submodule, or add it to .gitignore."
    }
  }
}
