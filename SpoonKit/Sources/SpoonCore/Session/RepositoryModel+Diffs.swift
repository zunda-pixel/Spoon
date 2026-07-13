extension RepositoryModel {
  public enum ChangeArea: Sendable, Hashable {
    case staged
    case unstaged
    case untracked
    case conflicted
  }

  /// Identifies one row in the Changes list for the detail column.
  public struct FileSelection: Sendable, Hashable {
    public var path: String
    public var area: ChangeArea

    public init(path: String, area: ChangeArea) {
      self.path = path
      self.area = area
    }
  }

  public func diff(for selection: FileSelection) async throws -> [FileDiff] {
    switch selection.area {
    case .staged:
      try await gitClient.diffWorkingTree(path: selection.path, staged: true)
    case .unstaged, .conflicted:
      try await gitClient.diffWorkingTree(path: selection.path, staged: false)
    case .untracked:
      [try await gitClient.untrackedFileDiff(path: selection.path)]
    }
  }

  public func commitDetail(_ oid: ObjectID) async throws -> CommitDetail {
    try await gitClient.commitDetail(oid)
  }
}
