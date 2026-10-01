public import Foundation

/// Repository working-tree queries and mutations.
public protocol GitWorkingTreeClient: Sendable {
  var repositoryRoot: URL { get }

  /// Absolute git and common directories of this checkout.
  func repositoryPaths() async throws -> GitRepositoryPaths

  func status() async throws -> WorkingTreeStatus

  /// Working-tree patch: index vs HEAD when `staged`, else worktree vs index.
  /// `path` narrows to one file; `nil` diffs everything.
  func diffWorkingTree(path: String?, staged: Bool, options: DiffOptions) async throws -> [FileDiff]
  /// Synthesized all-added diff for an untracked file.
  func untrackedFileDiff(path: String) async throws -> FileDiff
  /// Metadata, full message, and first-parent patch for one commit.
  /// Stages whole paths (also marks conflicted paths resolved).
  func stage(paths: [String]) async throws
  /// Stages conflicted paths as resolved. With
  /// `GitCapabilities.supportsAddResolved`, git refuses (staging nothing)
  /// while any path still contains conflict markers.
  func markResolved(paths: [String]) async throws
  /// Resolves one conflicted path by taking `side`'s version, or deleting
  /// the path when `side` has no version (`sideHasFile == false`).
  func resolveConflict(path: String, using side: FileStatusEntry.ConflictSide, sideHasFile: Bool)
    async throws
  /// Rewrites a conflicted path with fresh conflict markers, undoing any
  /// edits made while resolving it (`git checkout --merge`).
  func restoreConflictMarkers(path: String) async throws
  /// Conflicted paths rerere has not resolved from a recording
  /// (`git rerere remaining`); `nil` when rerere isn't tracking the
  /// current conflict, e.g. because it was off when the merge began.
  func rerereRemaining() async throws -> Set<String>?
  /// Drops rerere's recorded resolution for `path` (`git rerere forget`).
  func forgetRecordedResolution(path: String) async throws
  /// Deletes every resolution rerere has recorded (`.git/rr-cache`).
  func forgetAllRecordedResolutions() async throws
  /// Removes paths from the index, keeping working-tree contents.
  func unstage(paths: [String]) async throws
  /// Applies a patch (from `DiffPatchBuilder`). `toIndex` targets the index
  /// (`--cached`, hunk stage/unstage); false targets the working tree
  /// (line/hunk discard via reverse apply).
  func applyPatch(_ patch: String, reverse: Bool, toIndex: Bool) async throws
  /// Replaces the working-tree copy of `path` with its content at
  /// `revision`, leaving the index alone (`git restore --source`). A path
  /// tracked now but absent at `revision` is deleted.
  func restoreFile(path: String, from revision: ObjectID) async throws
  /// Restores paths from the index, discarding working-tree edits.
  func discardWorkingTree(paths: [String]) async throws
  /// Deletes untracked files.
  func deleteUntracked(paths: [String]) async throws
  /// Untracked paths the ignore rules hide, a wholly ignored folder as one
  /// `folder/` entry (`git ls-files --others --ignored --directory`).
  func ignoredPaths() async throws -> [String]
  /// The pattern that last matched each path (`git check-ignore`); `nil`
  /// for a path no pattern matches.
  func ignoreRules(for paths: [String]) async throws -> [String: IgnoreRule?]
  /// Whether `path` is in the index, where ignore rules don't apply.
  func isTracked(path: String) async throws -> Bool
  /// Deletes ignored files and folders under `paths`, or every ignored
  /// path when `paths` is empty (`git clean -f -d -X`). Tracked and
  /// merely untracked files are left alone.
  func deleteIgnored(paths: [String]) async throws
  /// Commits staged changes; message may be multi-line.
  func commit(message: String, options: CommitOptions) async throws
  /// Whether and how git signs new commits here (`commit.gpgSign`,
  /// `gpg.format`, `user.signingKey`).
  func commitSigningConfiguration() async throws -> CommitSigningConfiguration
  /// Every value of the settings Spoon edits, from every config file.
  func repositoryConfig() async throws -> RepositoryConfig
  /// Sets `setting` in this repository's `.git/config`, or removes it there
  /// when `value` is `nil` so the user's or system value applies again.
  func setRepositoryConfig(_ setting: RepositorySetting, to value: String?) async throws
  /// Commits the staged changes as `fixup! <subject of oid>`, to be folded
  /// into that commit later by `autosquash(onto:)`.
  func commitFixup(for oid: ObjectID) async throws
  func reset(to target: ObjectID, mode: ResetMode) async throws
}

/// Installed-git feature detection.
public protocol GitCapabilityClient: Sendable {
  /// Optional features of the installed git. Implementations may cache the
  /// result; an unknown version reports every gated feature as unavailable.
  func capabilities() async -> GitCapabilities
}

/// Commit history and reflog queries.
public protocol GitHistoryClient: Sendable {
  func log(_ query: LogQuery) async throws -> LogPage
  func commitDetail(_ oid: ObjectID, options: DiffOptions) async throws -> CommitDetail
  func reflog(maxCount: Int, skip: Int) async throws -> [ReflogEntry]
  /// Line-by-line authorship of `path`: the working-tree file when
  /// `revision` is `nil` (uncommitted lines use the zero OID), else the
  /// file at that revision.
  func blame(path: String, at revision: ObjectID?, options: BlameOptions) async throws
    -> [BlameLine]
  /// Files `blame.ignoreRevsFile` lists, which git reads on every blame.
  func blameIgnoreRevsFiles() async throws -> [String]
  /// Distinct authors of the most recent `limit` commits, newest first.
  func recentAuthors(limit: Int) async throws -> [CoAuthor]
  /// The commits, newest first, that changed `lines` (1-based, inclusive)
  /// of `path` as it is at HEAD, each with the diff of just those lines,
  /// following them as they move (`git log -L`). At most `limit` commits.
  func lineHistory(path: String, lines: ClosedRange<Int>, limit: Int) async throws
    -> [LineHistoryEntry]
  /// The commit's nearest earlier tag and the first tag containing it
  /// (`git describe`, counting lightweight tags too). Both are `nil` in a
  /// repository without tags.
  func describe(_ oid: ObjectID) async throws -> CommitDescription
  /// Lines matching `query` (`git grep`), at most `limit` of them.
  func searchCode(_ query: CodeSearchQuery, limit: Int) async throws -> CodeSearchResult
}

/// Local branch operations.
public protocol GitBranchClient: Sendable {
  func branches() async throws -> [Branch]
  func switchBranch(_ branch: String) async throws
  func switchToRevision(_ oid: ObjectID) async throws
  func createBranch(name: String, from startPoint: String?, switchToBranch: Bool) async throws
  func switchToRemoteBranch(_ remoteBranch: String) async throws
  func merge(branch: String, options: MergeOptions) async throws
  /// Simulates merging `branch` into HEAD with Git's default strategy and
  /// reports the paths that would conflict. Changes no refs, index, or files.
  func mergePreview(branch: String) async throws -> MergePreview
  func deleteBranch(name: String, force: Bool) async throws
  /// Whether every change of `branch` is already in `target`, even though
  /// git's own check (`branch -d`) does not see it: the branch was rebased
  /// onto `target` commit by commit, or squashed into a single commit there.
  func isContentMerged(branch: String, into target: String) async throws -> Bool
  /// Deletes local branches whose work already landed on the upstream they
  /// track (`git branch --delete-merged`, requires
  /// `GitCapabilities.supportsDeleteMergedBranches`). git skips branches
  /// checked out in any worktree, branches that push to their own upstream,
  /// bases of other branches, and `branch.<name>.deleteMerged = false`.
  /// `branches` restricts the candidates; empty means every local branch.
  /// Returns the branch names deleted, or that would be with `dryRun`.
  @discardableResult
  func deleteMergedBranches(branches: [String], dryRun: Bool) async throws -> [String]
  func renameBranch(from oldName: String, to newName: String) async throws
  /// Points a local branch at `target` without touching any worktree, only
  /// if it still points at `expectedTip` (`git refs update`, or
  /// `git update-ref` before git 2.56). The previous tip stays in the reflog.
  func moveBranch(name: String, to target: ObjectID, expectedTip: ObjectID) async throws
  func setUpstream(of branch: String, to upstream: String) async throws
  /// Names of local branches whose configured upstream is `upstream`, a
  /// full ref such as `refs/remotes/origin/main` or `refs/heads/main`.
  func branchNames(forkedFrom upstream: String) async throws -> [String]
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
  /// Pushes local `branch` to the same name on `remoteName` and sets it as upstream.
  func publishBranch(_ branch: String, to remoteName: String) async throws
  func fetch() async throws
  /// Whether this is a shallow clone, missing history beyond a boundary
  /// (`git rev-parse --is-shallow-repository`).
  func isShallowRepository() async throws -> Bool
  /// Fetches older history into a shallow clone from its default remote.
  func deepenHistory(_ depth: HistoryDepth) async throws
  /// Downloads blobs omitted by a partial clone (requires
  /// `GitCapabilities.supportsBackfill`).
  func backfill() async throws
  /// Objects reachable from HEAD that a partial clone has not downloaded
  /// (`rev-list --missing=print --missing-only`, requires
  /// `GitCapabilities.supportsRemoteObjectInfo`). Never fetches.
  func missingObjectIDs() async throws -> [ObjectID]
  /// Sizes in bytes the remote reports for `objects`, without downloading
  /// them (`cat-file --batch-command` `remote-object-info`, requires
  /// `GitCapabilities.supportsRemoteObjectInfo` and a server that
  /// advertises the `object-info` capability).
  func remoteObjectSizes(of objects: [ObjectID], from remoteName: String) async throws
    -> [ObjectID: Int]
  /// The promisor remote of a partial clone (`extensions.partialClone`), or
  /// `nil` for a full clone.
  func partialCloneRemote() async throws -> String?
  /// Deletes local blobs larger than `byteLimit` that the promisor remote can
  /// serve again on demand (`git repack -a -d --drop-filtered`, requires
  /// `GitCapabilities.supportsRepackDropFiltered`). git keeps blobs the index
  /// uses and refuses while a merge, rebase, or similar operation runs.
  func dropLargeBlobs(largerThan byteLimit: Int) async throws
  func pull(_ options: PullOptions) async throws
  /// Pushes the current branch; sets upstream on first push.
  func push(force: Bool) async throws
}

/// Tag queries and mutations.
public protocol GitTagClient: Sendable {
  func tags() async throws -> [Tag]
  /// Creates a lightweight tag, or an annotated one when `message` is set.
  /// A signed tag is always annotated; it uses `name` as the message when
  /// `message` is `nil`.
  func createTag(name: String, at target: ObjectID?, message: String?, signing: TagSigning)
    async throws
  func deleteTag(name: String) async throws
  /// Checks a tag's signature (`git verify-tag`); `nil` when it has none.
  func verifyTag(name: String) async throws -> CommitSignature?
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
  /// Forgets worktrees whose folders no longer exist (`git worktree prune`).
  func pruneWorktrees() async throws
  /// Protects a linked worktree from being pruned, moved, or removed.
  func lockWorktree(path: URL, reason: String?) async throws
  func unlockWorktree(path: URL) async throws
  /// Moves a linked worktree's folder and updates git's records of it.
  func moveWorktree(path: URL, to destination: URL) async throws
}

/// Submodule queries and mutations.
public protocol GitSubmoduleClient: Sendable {
  /// Top-level submodules, sorted by path; empty without `.gitmodules`.
  func submodules() async throws -> [Submodule]
  /// Initializes and checks out the recorded commit of each path, and of
  /// their own submodules (`git submodule update --init --recursive`).
  /// Empty `paths` updates every submodule.
  func updateSubmodules(paths: [String]) async throws
  /// Copies URLs from `.gitmodules` into the local config
  /// (`git submodule sync --recursive`). Empty `paths` syncs every one.
  func syncSubmodules(paths: [String]) async throws
  /// Clones `url` into `path` and stages it as a new submodule.
  func addSubmodule(url: String, path: String) async throws
  /// Empties the checkout at `path` and forgets its local configuration,
  /// keeping the submodule itself (`git submodule deinit`). git refuses a
  /// checkout with local changes unless `force`.
  func deinitializeSubmodule(path: String, force: Bool) async throws
  /// Removes the submodule at `path` from the repository: its checkout,
  /// its `.gitmodules` entry, and its gitlink, staged for the next commit
  /// (`git rm`). git refuses a checkout with local changes unless `force`.
  func removeSubmodule(path: String, force: Bool) async throws
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
  /// Rebases the commits after `base` so each `fixup!`, `squash!`, and
  /// `amend!` commit is folded into its target (`rebase -i --autosquash`,
  /// accepting git's generated todo list). May pause on conflicts.
  func autosquash(onto base: ObjectID) async throws
  /// Applies one commit onto HEAD, keeping its original message.
  func cherryPick(_ oid: ObjectID) async throws
  /// Adds one inverse commit with git's default revert message.
  func revert(_ oid: ObjectID) async throws
  /// Applies several commits onto HEAD in the given order (`git cherry-pick
  /// A B C`). May pause on a conflict, like a single pick.
  func cherryPick(_ oids: [ObjectID], options: CherryPickOptions) async throws
  /// Adds one revert commit per commit, in the given order.
  func revert(_ oids: [ObjectID], options: RevertOptions) async throws
  /// Removes one non-merge, non-root commit and replays its descendants onto
  /// its parent, updating every descendant local branch (`git history drop`,
  /// requires `GitCapabilities.supportsHistoryDrop`). Aborts without
  /// changing anything on conflicts, merges, or local changes it would
  /// overwrite. `dryRun` reports the ref updates without applying them.
  @discardableResult
  func dropCommit(_ oid: ObjectID, dryRun: Bool) async throws -> [RefUpdate]
  /// Replaces one commit's message and rewrites its descendants, without
  /// touching the index or worktree (`git history reword`, requires
  /// `GitCapabilities.supportsHistoryReword`).
  func rewordCommit(_ oid: ObjectID, message: String) async throws
  /// Folds the staged changes into an earlier commit, keeping its message,
  /// and replays its descendants (`git history fixup`, requires
  /// `GitCapabilities.supportsHistoryFixup`). Aborts without changing
  /// anything on conflicts. `dryRun` reports the ref updates only.
  @discardableResult
  func fixupCommit(_ oid: ObjectID, dryRun: Bool) async throws -> [RefUpdate]
  /// Rebases local `branch` onto `newBase` without touching the index or any
  /// worktree (`git replay`, requires `GitCapabilities.supportsReplayLinearize`).
  /// The branch is updated atomically, or not at all on conflicts.
  /// `linearize` drops merge commits and replays their commits individually.
  func replayBranch(_ branch: String, onto newBase: ObjectID, linearize: Bool) async throws
  /// `nil` when no rebase/cherry-pick/revert is in progress.
  func sequencerState() async throws -> SequencerState?
  func continueSequencer(_ kind: SequencerState.Kind) async throws
  func skipSequencer(_ kind: SequencerState.Kind) async throws
  func abortSequencer(_ kind: SequencerState.Kind) async throws
}

/// `git bisect` to find the commit that introduced a problem.
public protocol GitBisectClient: Sendable {
  /// `nil` when no bisect is in progress.
  func bisectState() async throws -> BisectState?
  /// Starts bisecting between a bad and a good commit and checks out the
  /// first commit to test. With `GitCapabilities.supportsBisectResetWhenFound`,
  /// git ends the bisect by itself once the culprit is found.
  func startBisect(bad: ObjectID, good: ObjectID) async throws -> BisectProgress
  /// Marks `revision` (HEAD when `nil`) and moves to the next commit to test.
  func markBisect(_ mark: BisectMark, revision: ObjectID?) async throws -> BisectProgress
  /// Tests commits with a shell command until the first bad one is found
  /// (`git bisect run`): exit status 0 marks good, 125 skip, and any other
  /// status below 128 bad. The command runs in a login shell at the
  /// repository root, so it sees the user's `PATH`.
  func runBisect(command: String) async throws -> BisectProgress
  /// Ends the bisect and returns to the commit checked out before it began.
  func resetBisect() async throws
}

/// Cross-reference diff operations used by review features.
public protocol GitReviewClient: Sendable {
  /// Merge base between two refs.
  func mergeBase(_ a: String, _ b: String) async throws -> ObjectID
  /// Unified diff between two refs (e.g. merge-base..HEAD for reviews).
  func diff(from: String, to: String) async throws -> [FileDiff]
  /// Raw unified diff text between two refs, for AI prompts.
  func diffText(from: String, to: String) async throws -> String
  /// How the commits of `new` correspond to those of `old`
  /// (`git range-diff <oldBase>..<oldTip> <newBase>..<newTip>`).
  func rangeDiff(
    oldBase: ObjectID, oldTip: ObjectID, newBase: ObjectID, newTip: ObjectID
  ) async throws -> [RangeDiffEntry]
  /// The commit `reference` pointed to before its latest move
  /// (`<reference>@{1}`), or `nil` when the reflog has no earlier entry.
  func previousTip(of reference: String) async throws -> ObjectID?
  /// Raw staged diff text, for AI prompts.
  func stagedDiffText() async throws -> String
}

/// Stash queries and mutations.
public protocol GitStashClient: Sendable {
  func stashes() async throws -> [Stash]
  func saveStash(_ options: StashSaveOptions) async throws
  func applyStash(_ stash: Stash, pop: Bool) async throws
  func dropStash(_ stash: Stash) async throws
  /// Creates branch `name` at the commit the stash was made on, switches to
  /// it, and applies the stash there, dropping it if that succeeds
  /// (`git stash branch`). The stash applies cleanly on its own base, so
  /// this recovers a stash that conflicts where it is.
  func branchFromStash(_ stash: Stash, name: String) async throws
  /// The changes a stash would reapply (its parent vs the stash commit).
  func stashDiffs(_ stash: Stash) async throws -> [FileDiff]
}

/// Backward-compatible aggregate used by existing UI, services, and fakes.
public protocol GitClient:
  GitCapabilityClient,
  GitWorkingTreeClient,
  GitHistoryClient,
  GitBranchClient,
  GitRemoteClient,
  GitTagClient,
  GitWorktreeClient,
  GitSubmoduleClient,
  GitSparseCheckoutClient,
  GitSequencerClient,
  GitBisectClient,
  GitReviewClient,
  GitStashClient
{}

extension GitStashClient {
  /// Stashes every change, optionally including untracked files.
  public func saveStash(message: String?, includeUntracked: Bool) async throws {
    try await saveStash(StashSaveOptions(message: message, includeUntracked: includeUntracked))
  }
}

extension GitWorkingTreeClient {
  public func commit(message: String, amend: Bool) async throws {
    try await commit(message: message, options: CommitOptions(amend: amend))
  }

  public func diffWorkingTree(path: String?, staged: Bool) async throws -> [FileDiff] {
    try await diffWorkingTree(path: path, staged: staged, options: .standard)
  }
}

extension GitTagClient {
  public func createTag(name: String, at target: ObjectID?, message: String?) async throws {
    try await createTag(name: name, at: target, message: message, signing: .configured)
  }
}

extension GitSequencerClient {
  public func cherryPick(_ oids: [ObjectID]) async throws {
    try await cherryPick(oids, options: CherryPickOptions())
  }

  public func revert(_ oids: [ObjectID]) async throws {
    try await revert(oids, options: RevertOptions())
  }
}

extension GitHistoryClient {
  public func blame(path: String, at revision: ObjectID?) async throws -> [BlameLine] {
    try await blame(path: path, at: revision, options: BlameOptions())
  }

  public func commitDetail(_ oid: ObjectID) async throws -> CommitDetail {
    try await commitDetail(oid, options: .standard)
  }
}
