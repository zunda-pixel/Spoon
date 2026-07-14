public import Foundation

/// Repository working-tree queries and mutations.
public protocol GitWorkingTreeClient: Sendable {
  var repositoryRoot: URL { get }

  func status() async throws -> WorkingTreeStatus

  /// Working-tree patch: index vs HEAD when `staged`, else worktree vs index.
  /// `path` narrows to one file; `nil` diffs everything.
  func diffWorkingTree(path: String?, staged: Bool) async throws -> [FileDiff]
  /// Synthesized all-added diff for an untracked file.
  func untrackedFileDiff(path: String) async throws -> FileDiff
  /// Metadata, full message, and first-parent patch for one commit.
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
}

/// Commit history and reflog queries.
public protocol GitHistoryClient: Sendable {
  func log(_ query: LogQuery) async throws -> LogPage
  func commitDetail(_ oid: ObjectID) async throws -> CommitDetail
  func reflog(maxCount: Int, skip: Int) async throws -> [ReflogEntry]
}

/// Local branch operations.
public protocol GitBranchClient: Sendable {
  func branches() async throws -> [Branch]
  func switchBranch(_ branch: String) async throws
  func switchToRevision(_ oid: ObjectID) async throws
  func createBranch(name: String, from startPoint: String?, switchToBranch: Bool) async throws
  func switchToRemoteBranch(_ remoteBranch: String) async throws
  func merge(branch: String, options: MergeOptions) async throws
  func deleteBranch(name: String, force: Bool) async throws
  func renameBranch(from oldName: String, to newName: String) async throws
  func setUpstream(of branch: String, to upstream: String) async throws
  func defaultBranch() async throws -> String
}

/// Remote configuration and synchronization.
public protocol GitRemoteClient: Sendable {
  func remotes() async throws -> [Remote]
  /// Remote-tracking branches of one remote (`refs/remotes/<name>`).
  func remoteBranches(of remoteName: String) async throws -> [Branch]
  func addRemote(name: String, url: String) async throws
  func setRemoteURL(name: String, fetchURL: String, pushURL: String?) async throws
  func removeRemote(name: String) async throws
  /// Pushes the existing remote-tracking ref under a new name, then deletes the old ref.
  /// This is intentionally non-atomic: a delete failure leaves both remote refs.
  func renameRemoteBranch(
    remoteName: String,
    from oldName: String,
    to newName: String
  ) async throws
  func deleteRemoteBranch(name: String, from remoteName: String) async throws
  func fetch() async throws
  /// Whether the installed git provides `git backfill` (2.49+).
  func supportsBackfill() async -> Bool
  /// Downloads blobs omitted by a partial clone.
  func backfill() async throws
  func pull() async throws
  /// Pushes the current branch; sets upstream on first push.
  func push(force: Bool) async throws
}

/// Tag queries and mutations.
public protocol GitTagClient: Sendable {
  func tags() async throws -> [Tag]
  func createTag(name: String, at target: ObjectID?, message: String?) async throws
  func deleteTag(name: String) async throws
  func pushTag(name: String, to remoteName: String) async throws
  func pushAllTags(to remoteName: String) async throws
  func deleteRemoteTag(name: String, from remoteName: String) async throws
}

/// Linked-worktree operations.
public protocol GitWorktreeClient: Sendable {
  /// All worktrees of this repository, main worktree first.
  func worktrees() async throws -> [Worktree]
  /// Creates a linked worktree at `path` checked out to existing `branch`.
  func addWorktree(path: URL, branch: String) async throws
  /// Creates a local tracking branch and checks it out in a linked worktree.
  func addWorktree(path: URL, remoteBranch: String, localBranch: String) async throws
  /// Removes a linked worktree (`--force` discards its local changes).
  func removeWorktree(path: URL, force: Bool) async throws
}

/// Sparse-checkout configuration.
public protocol GitSparseCheckoutClient: Sendable {
  /// Current cone-mode sparse paths; `nil` when sparse checkout is disabled.
  func sparseCheckoutPaths() async throws -> [String]?
  func setSparseCheckout(paths: [String]) async throws
  func disableSparseCheckout() async throws
}

/// Rebase, cherry-pick, revert, and merge sequencer operations.
public protocol GitSequencerClient: Sendable {
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
}

/// Cross-reference diff operations used by review features.
public protocol GitReviewClient: Sendable {
  /// Merge base between two refs.
  func mergeBase(_ a: String, _ b: String) async throws -> ObjectID
  /// Unified diff between two refs (e.g. merge-base..HEAD for reviews).
  func diff(from: String, to: String) async throws -> [FileDiff]
  /// Raw unified diff text between two refs, for AI prompts.
  func diffText(from: String, to: String) async throws -> String
  /// Raw staged diff text, for AI prompts.
  func stagedDiffText() async throws -> String
}

/// Stash queries and mutations.
public protocol GitStashClient: Sendable {
  func stashes() async throws -> [Stash]
  func saveStash(message: String?, includeUntracked: Bool) async throws
  func applyStash(_ stash: Stash, pop: Bool) async throws
  func dropStash(_ stash: Stash) async throws
  /// The changes a stash would reapply (its parent vs the stash commit).
  func stashDiffs(_ stash: Stash) async throws -> [FileDiff]
}

/// Backward-compatible aggregate used by existing UI, services, and fakes.
public protocol GitClient:
  GitWorkingTreeClient,
  GitHistoryClient,
  GitBranchClient,
  GitRemoteClient,
  GitTagClient,
  GitWorktreeClient,
  GitSparseCheckoutClient,
  GitSequencerClient,
  GitReviewClient,
  GitStashClient
{}
