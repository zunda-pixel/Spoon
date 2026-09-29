/// How `git cherry-pick` applies commits.
public struct CherryPickOptions: Sendable, Hashable {
  /// The parent, from 1, whose side of a merge commit counts as the base:
  /// the merge's changes are taken relative to it (`--mainline`). git
  /// accepts it for ordinary commits too, so a mixed list can use it.
  public var mainline: Int?
  /// Append "(cherry picked from commit …)" to each message (`-x`), as
  /// backports usually do.
  public var recordsOrigin: Bool
  /// Apply the changes to the index and working tree without committing
  /// (`--no-commit`).
  public var commits: Bool

  public init(mainline: Int? = nil, recordsOrigin: Bool = false, commits: Bool = true) {
    self.mainline = mainline
    self.recordsOrigin = recordsOrigin
    self.commits = commits
  }

  var arguments: [String] {
    var arguments = mainline.map { ["--mainline", String($0)] } ?? []
    if recordsOrigin { arguments.append("-x") }
    if !commits { arguments.append("--no-commit") }
    return arguments
  }
}

/// How `git revert` undoes commits.
public struct RevertOptions: Sendable, Hashable {
  /// As for `CherryPickOptions.mainline`: the parent a merge is undone
  /// back to.
  public var mainline: Int?
  /// Undo the changes in the index and working tree without committing
  /// (`--no-commit`).
  public var commits: Bool

  public init(mainline: Int? = nil, commits: Bool = true) {
    self.mainline = mainline
    self.commits = commits
  }

  var arguments: [String] {
    var arguments = mainline.map { ["--mainline", String($0)] } ?? []
    if !commits { arguments.append("--no-commit") }
    return arguments
  }
}
