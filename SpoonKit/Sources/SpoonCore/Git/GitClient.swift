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
  func reflog(maxCount: Int, skip: Int) async throws -> [ReflogEntry]

  /// Stages whole paths (also marks conflicted paths resolved).
  func stage(paths: [String]) async throws
  /// Removes paths from the index, keeping working-tree contents.
  func unstage(paths: [String]) async throws
  /// Applies a patch (from `DiffPatchBuilder`). `toIndex` targets the index
  /// (`--cached`, hunk stage/unstage); false targets the working tree
  /// (line/hunk discard via reverse apply).
  func applyPatch(_ patch: String, reverse: Bool, toIndex: Bool) async throws
  /// Restores paths from the index, discarding working-tree edits.
  func discardWorkingTree(paths: [String]) async throws
  /// Deletes untracked files.
  func deleteUntracked(paths: [String]) async throws
  /// Commits staged changes; message may be multi-line.
  func commit(message: String, amend: Bool) async throws
  func reset(to target: ObjectID, mode: ResetMode) async throws

  /// Remote-tracking branches of one remote (`refs/remotes/<name>`).
  func remoteBranches(of remoteName: String) async throws -> [Branch]
  func addRemote(name: String, url: String) async throws
  func setRemoteURL(name: String, fetchURL: String, pushURL: String?) async throws
  func removeRemote(name: String) async throws

  func checkout(branch: String) async throws
  /// Checks out a commit directly (detached HEAD).
  func checkoutRevision(_ oid: ObjectID) async throws
  /// Creates a branch at `startPoint` (HEAD when nil), optionally checking
  /// it out.
  func createBranch(name: String, from startPoint: String?, checkout: Bool) async throws
  /// Creates and checks out a local tracking branch for a remote-tracking
  /// branch like `origin/feature`.
  func checkoutRemoteBranch(_ remoteBranch: String) async throws

  /// Merges `branch` into the current branch using the selected fast-forward,
  /// commit, strategy, and conflict-preference behavior.
  func merge(branch: String, options: MergeOptions) async throws

  func tags() async throws -> [Tag]
  /// Creates a tag at `target` (HEAD when nil); a non-empty `message` makes
  /// it an annotated tag.
  func createTag(name: String, at target: ObjectID?, message: String?) async throws
  func deleteTag(name: String) async throws
  /// Pushes one local tag to a remote.
  func pushTag(name: String, to remoteName: String) async throws
  /// Pushes every local tag to a remote.
  func pushAllTags(to remoteName: String) async throws
  /// Deletes a tag from a remote without changing the local tag.
  func deleteRemoteTag(name: String, from remoteName: String) async throws
  /// Deletes a local branch (`-d`, or `-D` when `force`).
  func deleteBranch(name: String, force: Bool) async throws
  /// Renames a local branch (`branch -m`); works on the current branch too.
  func renameBranch(from oldName: String, to newName: String) async throws
  func fetch() async throws
  /// Whether the installed git provides `git backfill` (2.49+).
  func supportsBackfill() async -> Bool
  /// Downloads blobs omitted by a partial clone.
  func backfill() async throws
  func pull() async throws
  /// Pushes the current branch; sets upstream on first push.
  func push(force: Bool) async throws

  /// All worktrees of this repository, main worktree first.
  func worktrees() async throws -> [Worktree]
  /// Creates a linked worktree at `path` checked out to existing `branch`.
  func addWorktree(path: URL, branch: String) async throws
  /// Removes a linked worktree (`--force` discards its local changes).
  func removeWorktree(path: URL, force: Bool) async throws

  /// Current cone-mode sparse paths; `nil` when sparse checkout is disabled.
  func sparseCheckoutPaths() async throws -> [String]?
  func setSparseCheckout(paths: [String]) async throws
  func disableSparseCheckout() async throws

  /// Runs a headless `rebase -i` driven by `plan`'s todo list. May return
  /// with the rebase paused (edit step or conflict) — check `sequencerState()`.
  func interactiveRebase(_ plan: RebasePlan) async throws
  /// Applies one commit onto HEAD, keeping its original message.
  func cherryPick(_ oid: ObjectID) async throws
  /// Adds one inverse commit with git's default revert message.
  func revert(_ oid: ObjectID) async throws
  /// `nil` when no rebase/cherry-pick/revert is in progress.
  func sequencerState() async throws -> SequencerState?
  func continueSequencer(_ kind: SequencerState.Kind) async throws
  func skipSequencer(_ kind: SequencerState.Kind) async throws
  func abortSequencer(_ kind: SequencerState.Kind) async throws

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
  /// The changes a stash would reapply (its parent vs the stash commit).
  func stashDiffs(_ stash: Stash) async throws -> [FileDiff]
}
