/// Where one side of a file diff's content can be read from.
public enum FileVersion: Sendable, Hashable {
  /// The file in a commit or other tree-ish (`<revision>:<path>`).
  case revision(String)
  /// The index's stage-0 entry (`:0:<path>`).
  case index
  /// The file on disk.
  case workingTree

  /// The object name `git cat-file` reads, or `nil` for the working tree.
  public func objectName(path: String) -> String? {
    switch self {
    case .revision(let revision): "\(revision):\(path)"
    case .index: ":0:\(path)"
    case .workingTree: nil
    }
  }
}
