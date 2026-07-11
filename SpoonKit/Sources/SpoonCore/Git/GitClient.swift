public import Foundation

/// The seam UI and services depend on for repository state.
/// M1 surface: read-only queries. Mutations (stage/commit/checkout/…) land in M2.
public protocol GitClient: Sendable {
  var repositoryRoot: URL { get }

  func status() async throws -> WorkingTreeStatus
  func branches() async throws -> [Branch]
  func remotes() async throws -> [Remote]
  func log(_ query: LogQuery) async throws -> LogPage

  /// Working-tree patch: index vs HEAD when `staged`, else worktree vs index.
  /// `path` narrows to one file; `nil` diffs everything.
  func diffWorkingTree(path: String?, staged: Bool) async throws -> [FileDiff]
  /// Synthesized all-added diff for an untracked file.
  func untrackedFileDiff(path: String) async throws -> FileDiff
  /// Metadata, full message, and first-parent patch for one commit.
  func commitDetail(_ oid: ObjectID) async throws -> CommitDetail

  /// Stages whole paths (also marks conflicted paths resolved).
  func stage(paths: [String]) async throws
  /// Removes paths from the index, keeping working-tree contents.
  func unstage(paths: [String]) async throws
  /// Applies a patch (from `DiffPatchBuilder`) to the index.
  func applyPatch(_ patch: String, reverse: Bool) async throws
  /// Restores paths from the index, discarding working-tree edits.
  func discardWorkingTree(paths: [String]) async throws
  /// Deletes untracked files.
  func deleteUntracked(paths: [String]) async throws
  /// Commits staged changes; message may be multi-line.
  func commit(message: String, amend: Bool) async throws

  func checkout(branch: String) async throws
  func createBranch(name: String, checkout: Bool) async throws
  func fetch() async throws
  func pull() async throws
  /// Pushes the current branch; sets upstream on first push.
  func push(force: Bool) async throws

  /// Merge base between two refs.
  func mergeBase(_ a: String, _ b: String) async throws -> ObjectID
  /// Default branch short name (from origin/HEAD, falling back to main/master).
  func defaultBranch() async throws -> String
  /// Unified diff between two refs (e.g. merge-base..HEAD for reviews).
  func diff(from: String, to: String) async throws -> [FileDiff]
  /// Raw unified diff text between two refs, for AI prompts.
  func diffText(from: String, to: String) async throws -> String
  /// Raw staged diff text, for AI prompts.
  func stagedDiffText() async throws -> String

  func stashes() async throws -> [Stash]
  func saveStash(message: String?, includeUntracked: Bool) async throws
  func applyStash(_ stash: Stash, pop: Bool) async throws
  func dropStash(_ stash: Stash) async throws
}
