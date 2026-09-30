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

  /// What discarding a selection of Changes rows does: unstaged edits are
  /// reverted to the index and untracked files deleted. Staged and
  /// conflicted rows are left out.
  public struct DiscardPlan: Sendable, Hashable {
    public var modifiedPaths: [String]
    public var untrackedPaths: [String]

    public init(_ selections: some Collection<FileSelection>) {
      modifiedPaths = selections.filter { $0.area == .unstaged }.map(\.path).sorted()
      untrackedPaths = selections.filter { $0.area == .untracked }.map(\.path).sorted()
    }

    public var isEmpty: Bool { modifiedPaths.isEmpty && untrackedPaths.isEmpty }
    public var count: Int { modifiedPaths.count + untrackedPaths.count }

    /// "Discard changes to 3 files and delete 2 untracked files?"
    public var question: String {
      func files(_ count: Int) -> String { count == 1 ? "1 file" : "\(count) files" }
      func untracked(_ count: Int) -> String {
        count == 1 ? "1 untracked file" : "\(count) untracked files"
      }
      switch (modifiedPaths.count, untrackedPaths.count) {
      case (0, let deleted): return "Delete \(untracked(deleted))?"
      case (let reverted, 0): return "Discard changes to \(files(reverted))?"
      case (let reverted, let deleted):
        return "Discard changes to \(files(reverted)) and delete \(untracked(deleted))?"
      }
    }
  }

  public func diff(for selection: FileSelection) async throws -> [FileDiff] {
    switch selection.area {
    case .staged:
      try await gitClient.diffWorkingTree(path: selection.path, staged: true, options: diffOptions)
    case .unstaged, .conflicted:
      try await gitClient.diffWorkingTree(
        path: selection.path, staged: false, options: diffOptions)
    case .untracked:
      [try await gitClient.untrackedFileDiff(path: selection.path)]
    }
  }

  public func commitDetail(_ oid: ObjectID) async throws -> CommitDetail {
    try await gitClient.commitDetail(oid, options: diffOptions)
  }

  /// The diff settings chosen in the View menu.
  public var diffOptions: DiffOptions {
    DiffOptions(ignoresWhitespace: diffIgnoresWhitespace)
  }
}
