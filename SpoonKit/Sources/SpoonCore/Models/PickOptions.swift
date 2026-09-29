/// How `git cherry-pick` applies commits.
public struct CherryPickOptions: Sendable, Hashable {
  /// The parent, from 1, whose side of a merge commit counts as the base:
  /// the merge's changes are taken relative to it (`--mainline`). git
  /// accepts it for ordinary commits too, so a mixed list can use it.
  public var mainline: Int?

  public init(mainline: Int? = nil) {
    self.mainline = mainline
  }

  var arguments: [String] {
    mainline.map { ["--mainline", String($0)] } ?? []
  }
}

/// How `git revert` undoes commits.
public struct RevertOptions: Sendable, Hashable {
  /// As for `CherryPickOptions.mainline`: the parent a merge is undone
  /// back to.
  public var mainline: Int?

  public init(mainline: Int? = nil) {
    self.mainline = mainline
  }

  var arguments: [String] {
    mainline.map { ["--mainline", String($0)] } ?? []
  }
}
