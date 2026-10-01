public import Foundation
import Defaults
public import MemberwiseInit

extension RepositoryModel {
  /// Stages paths; conflicted ones are marked resolved, so on git 2.56+
  /// a file that still has conflict markers is refused instead of staged.
  public func stage(paths: [String]) async {
    let conflicted = Set(status?.conflictedEntries.map(\.path) ?? [])
    let resolved = paths.filter(conflicted.contains)
    let others = paths.filter { !conflicted.contains($0) }
    await perform {
      if !others.isEmpty {
        try await $0.stage(paths: others)
      }
      if !resolved.isEmpty {
        try await $0.markResolved(paths: resolved)
      }
    }
  }

  /// Resolves a conflicted path by taking one side's version of the file.
  public func resolveConflict(_ entry: FileStatusEntry, using side: FileStatusEntry.ConflictSide)
    async
  {
    guard entry.conflict != nil else { return }
    await perform {
      try await $0.resolveConflict(
        path: entry.path,
        using: side,
        sideHasFile: entry.conflictSideHasFile(side)
      )
    }
  }

  public func unstage(paths: [String]) async {
    await perform { try await $0.unstage(paths: paths) }
  }

  /// Puts `path` in the working tree back to how it was at `revision`.
  public func restoreFile(path: String, from revision: ObjectID) async {
    await perform { try await $0.restoreFile(path: path, from: revision) }
  }

  public func discardWorkingTree(paths: [String]) async {
    await perform { try await $0.discardWorkingTree(paths: paths) }
  }

  public func deleteUntracked(paths: [String]) async {
    await perform { try await $0.deleteUntracked(paths: paths) }
  }

  /// Makes git stop (or resume) noticing local changes to tracked
  /// `paths`, e.g. a config file edited only on this machine.
  public func setSkipWorktree(paths: [String], skip: Bool) async {
    await perform { try await $0.setSkipWorktree(paths: paths, skip: skip) }
  }

  /// Reverts the plan's unstaged edits and deletes its untracked files.
  public func discard(_ plan: DiscardPlan) async {
    guard !plan.isEmpty else { return }
    await perform {
      if !plan.modifiedPaths.isEmpty {
        try await $0.discardWorkingTree(paths: plan.modifiedPaths)
      }
      if !plan.untrackedPaths.isEmpty {
        try await $0.deleteUntracked(paths: plan.untrackedPaths)
      }
    }
  }

  public func stageHunk(_ hunkID: Hunk.ID, of diff: FileDiff) async {
    guard let patch = DiffPatchBuilder.patch(for: diff, including: [hunkID]) else { return }
    await perform { try await $0.applyPatch(patch, reverse: false, toIndex: true) }
  }

  public func unstageHunk(_ hunkID: Hunk.ID, of diff: FileDiff) async {
    guard let patch = DiffPatchBuilder.patch(for: diff, including: [hunkID]) else { return }
    await perform { try await $0.applyPatch(patch, reverse: true, toIndex: true) }
  }

  public func discardLines(_ offsets: Set<Int>, of hunkID: Hunk.ID, in diff: FileDiff) async {
    guard
      let patch = DiffPatchBuilder.discardPatch(
        for: diff, hunkID: hunkID, selectedOffsets: offsets)
    else { return }
    await perform { try await $0.applyPatch(patch, reverse: true, toIndex: false) }
  }

  public func discardHunk(_ hunkID: Hunk.ID, of diff: FileDiff) async {
    guard let hunk = diff.hunks.first(where: { $0.id == hunkID }) else { return }
    await discardLines(DiffPatchBuilder.changedLineOffsets(of: hunk), of: hunkID, in: diff)
  }

  public func unstageLines(_ offsets: Set<Int>, of hunkID: Hunk.ID, in diff: FileDiff) async {
    guard
      let patch = DiffPatchBuilder.discardPatch(
        for: diff, hunkID: hunkID, selectedOffsets: offsets)
    else { return }
    await perform { try await $0.applyPatch(patch, reverse: true, toIndex: true) }
  }

  public func commit(message: String, amend: Bool = false) async -> Bool {
    await commit(message: message, options: CommitOptions(amend: amend, signOff: commitSignsOff))
  }

  /// Commits with `options`, crediting `commitCoAuthors` too; they are
  /// remembered for later and cleared once the commit succeeds.
  public func commit(message: String, options: CommitOptions) async -> Bool {
    var options = options
    let coAuthors = commitCoAuthors
    options.trailers += coAuthors.map(\.trailer)
    let succeeded = await perform { try await $0.commit(message: message, options: options) }
    if succeeded, !coAuthors.isEmpty {
      remember(coAuthors)
      commitCoAuthors = []
    }
    return succeeded
  }

  /// Co-authors used before, most recent first, for the composer to offer.
  public var rememberedCoAuthors: [CoAuthor] { Defaults[.coAuthors] }

  public func remember(_ coAuthors: [CoAuthor]) {
    let ids = Set(coAuthors.map(\.id))
    Defaults[.coAuthors] = Array((coAuthors + Defaults[.coAuthors].filter { !ids.contains($0.id) }).prefix(20))
  }

  public func forget(_ coAuthor: CoAuthor) {
    Defaults[.coAuthors].removeAll { $0.id == coAuthor.id }
    commitCoAuthors.removeAll { $0.id == coAuthor.id }
  }

  /// Recent commit authors, as co-author suggestions.
  public func recentAuthors() async -> [CoAuthor] {
    (try? await gitClient.recentAuthors(limit: 500)) ?? []
  }

  /// The repository's signing settings; `nil` when git config can't be read.
  public func commitSigningConfiguration() async -> CommitSigningConfiguration? {
    try? await gitClient.commitSigningConfiguration()
  }

  public func reset(to target: ObjectID, mode: ResetMode) async {
    await perform { try await $0.reset(to: target, mode: mode) }
  }

  public func remoteBranches(of remoteName: String) async throws -> [Branch] {
    try await gitClient.remoteBranches(of: remoteName)
  }

  public func addRemote(name: String, url: String) async {
    await perform { try await $0.addRemote(name: name, url: url) }
  }

  public func setRemoteURL(name: String, fetchURL: String, pushURL: String?) async {
    await perform {
      try await $0.setRemoteURL(name: name, fetchURL: fetchURL, pushURL: pushURL)
    }
  }

  public func removeRemote(name: String) async {
    await perform { try await $0.removeRemote(name: name) }
  }

  public func switchBranch(_ branch: String) async {
    await perform { try await $0.switchBranch(branch) }
  }

  public func switchToRevision(_ oid: ObjectID) async {
    await perform { try await $0.switchToRevision(oid) }
  }

  public func mergePreview(branch: String) async throws -> MergePreview {
    try await gitClient.mergePreview(branch: branch)
  }

  public func merge(branch: String, options: MergeOptions = .standard) async {
    await perform { try await $0.merge(branch: branch, options: options) }
  }

  public func createTag(
    name: String,
    at target: ObjectID?,
    message: String?,
    signing: TagSigning = .configured,
    pushToRemotes: Bool = false
  ) async {
    let remoteNames = pushToRemotes ? remotes.map(\.name) : []
    await perform {
      try await $0.createTag(name: name, at: target, message: message, signing: signing)
      for remoteName in remoteNames {
        try await $0.pushTag(name: name, to: remoteName)
      }
    }
  }

  /// Verifies every signed tag on `oid`, in name order; unverifiable
  /// results are kept so the UI can say so.
  public func verifiedTags(at oid: ObjectID) async -> [(tag: Tag, signature: CommitSignature)] {
    var results: [(tag: Tag, signature: CommitSignature)] = []
    for tag in tags.filter({ $0.target == oid && $0.isSigned }).sorted(by: { $0.name < $1.name }) {
      if let signature = try? await gitClient.verifyTag(name: tag.name) {
        results.append((tag, signature))
      }
    }
    return results
  }

  public func deleteTag(name: String) async {
    await perform { try await $0.deleteTag(name: name) }
  }

  public func pushTag(name: String, to remoteName: String) async {
    await perform { try await $0.pushTag(name: name, to: remoteName) }
  }

  public func pushAllTags(to remoteName: String) async {
    await perform { try await $0.pushAllTags(to: remoteName) }
  }

  public func deleteRemoteTag(name: String, from remoteName: String) async {
    await perform { try await $0.deleteRemoteTag(name: name, from: remoteName) }
  }

  public func createBranch(
    name: String, from startPoint: String? = nil, switchToBranch: Bool = true
  ) async {
    await perform {
      try await $0.createBranch(
        name: name,
        from: startPoint,
        switchToBranch: switchToBranch
      )
    }
  }

  public func switchToRemoteBranch(_ remoteBranch: String) async {
    await perform { try await $0.switchToRemoteBranch(remoteBranch) }
  }

  /// The branch's upstream when it is a remote-tracking branch that still
  /// exists. `nil` for no upstream, a local upstream, or one that is gone
  /// (deleted on the remote and pruned by fetch), so the rename/delete
  /// sheets only offer to change remote branches that are actually there.
  public func existingRemoteUpstream(of branch: Branch) -> String? {
    guard
      let upstream = branch.upstream, !branch.upstreamGone,
      let remoteName = branch.upstreamRemoteName,
      remoteBranchesByRemote[remoteName]?.contains(where: { $0.name == upstream }) == true
    else { return nil }
    return upstream
  }

  /// Whether `git branch -d` would refuse to delete `branch`: git allows a
  /// plain delete when the tip is reachable from HEAD or from the branch's
  /// own upstream; anything else discards commits and needs `-D`.
  public func requiresForceDelete(_ branch: Branch) async -> Bool {
    if branch.upstream != nil, !branch.upstreamGone, branch.ahead == 0 {
      return false
    }
    guard let head = status?.headOID else { return true }
    if branch.tip == head { return false }
    if let base = try? await gitClient.mergeBase(branch.name, "HEAD"), base == branch.tip {
      return false
    }
    return true
  }

  /// How safe deleting a local branch is.
  public enum BranchDeletionSafety: Sendable, Hashable {
    /// `git branch -d` accepts it.
    case merged
    /// git needs `-D`, but every change is already in `target` (a squash or
    /// rebase merge), so nothing is lost.
    case contentMerged(into: String)
    /// Deleting discards commits that exist nowhere else.
    case unmerged

    /// Whether the delete must use `-D`.
    public var requiresForce: Bool { self != .merged }
  }

  public func deletionSafety(of branch: Branch) async -> BranchDeletionSafety {
    guard await requiresForceDelete(branch) else { return .merged }
    if let target = await contentMergedTarget(of: branch) {
      return .contentMerged(into: target)
    }
    return .unmerged
  }

  /// The branch whose history already contains `branch`'s changes although
  /// `git branch -d` refuses it, typically after a squash or rebase merge on
  /// GitHub. Checks HEAD, the default branch, and its remote-tracking copy
  /// (which is ahead after merging a pull request and fetching).
  public func contentMergedTarget(of branch: Branch) async -> String? {
    guard let defaultBranch = try? await gitClient.defaultBranch() else { return nil }
    var targets = ["HEAD", defaultBranch]
    if remotes.contains(where: { $0.name == "origin" }) {
      targets.append("origin/\(defaultBranch)")
    }
    let knownRefs =
      Set(branches.map(\.name))
      .union(remoteBranchesByRemote.values.flatMap { $0.map(\.name) })
    for target in targets where target == "HEAD" || knownRefs.contains(target) {
      if (try? await gitClient.isContentMerged(branch: branch.name, into: target)) == true {
        return target == "HEAD" ? (currentBranch?.name ?? "HEAD") : target
      }
    }
    return nil
  }

  public func deleteBranch(
    name: String,
    force: Bool = false,
    deleteRemoteUpstream upstream: String? = nil
  ) async {
    await perform {
      try await $0.deleteBranch(name: name, force: force)
      if let upstream,
        let (remoteName, remoteBranch) = Self.remoteBranchComponents(of: upstream)
      {
        try await $0.deleteRemoteBranch(name: remoteBranch, from: remoteName)
      }
    }
  }

  /// Local branches `git branch --delete-merged` would remove because their
  /// work already landed on the upstream they track.
  public func mergedBranchesToDelete() async throws -> [String] {
    try await gitClient.deleteMergedBranches(branches: [], dryRun: true)
  }

  /// Deletes the merged branches previewed by `mergedBranchesToDelete`.
  /// git re-checks each one, so a branch that changed since the preview is kept.
  public func deleteMergedBranches(_ names: [String]) async {
    guard !names.isEmpty else { return }
    await perform { try await $0.deleteMergedBranches(branches: names, dryRun: false) }
  }

  /// One branch of a bulk delete.
  @MemberwiseInit(.public)
  public struct BranchDeletion: Sendable, Hashable {
    public var name: String
    public var force: Bool
    /// `remote/branch` to delete from its remote as well, if any.
    public var remoteUpstream: String? = nil
  }

  /// Deletes several local branches, and optionally their remote branches,
  /// in order. Stops at the first failure; earlier deletions stay done.
  public func deleteBranches(_ deletions: [BranchDeletion]) async {
    guard !deletions.isEmpty else { return }
    await perform {
      for deletion in deletions {
        try await $0.deleteBranch(name: deletion.name, force: deletion.force)
        if let upstream = deletion.remoteUpstream,
          let (remoteName, remoteBranch) = Self.remoteBranchComponents(of: upstream)
        {
          try await $0.deleteRemoteBranch(name: remoteBranch, from: remoteName)
        }
      }
    }
  }

  public func renameBranch(
    from oldName: String,
    to newName: String,
    renameRemoteUpstream upstream: String? = nil
  ) async {
    await perform {
      try await $0.renameBranch(from: oldName, to: newName)
      if let upstream,
        let (remoteName, oldRemoteBranch) = Self.remoteBranchComponents(of: upstream)
      {
        try await $0.renameRemoteBranch(
          remoteName: remoteName,
          from: oldRemoteBranch,
          to: newName
        )
        try await $0.setUpstream(of: newName, to: "\(remoteName)/\(newName)")
      }
    }
  }

  /// Local branches that "Move Branch Here" can repoint at `commit`. The
  /// current branch and branches checked out in a worktree are excluded:
  /// moving them would leave that worktree's files and index behind.
  public func branchesMovable(to commit: ObjectID) -> [Branch] {
    branches.filter { branch in
      !branch.isCurrent && branch.tip != commit && worktree(for: branch) == nil
    }
  }

  public func moveBranch(_ branch: Branch, to target: ObjectID) async {
    await perform {
      try await $0.moveBranch(name: branch.name, to: target, expectedTip: branch.tip)
    }
  }

  public func renameRemoteBranch(
    remoteName: String,
    from oldName: String,
    to newName: String
  ) async {
    await perform {
      try await $0.renameRemoteBranch(
        remoteName: remoteName,
        from: oldName,
        to: newName
      )
    }
  }

  /// Pushes `branch` to a remote first when it has no live upstream, so that
  /// GitHub's compare page has a head branch to open a pull request from.
  /// Returns the refreshed branch, or `nil` when the push failed.
  public func publishBranchForPullRequest(_ branch: Branch) async -> Branch? {
    guard branch.upstream == nil || branch.upstreamGone,
      let remoteName = pullRequestRemoteName(for: branch)
    else { return branch }
    let succeeded = await perform {
      try await $0.publishBranch(branch.name, to: remoteName)
    }
    guard succeeded else { return nil }
    return branches.first { $0.name == branch.name } ?? branch
  }

  /// The branch's own upstream remote when still configured, else `origin`,
  /// else the first remote.
  private func pullRequestRemoteName(for branch: Branch) -> String? {
    let names = remotes.map(\.name)
    if let upstreamRemoteName = branch.upstreamRemoteName, names.contains(upstreamRemoteName) {
      return upstreamRemoteName
    }
    return names.contains("origin") ? "origin" : names.first
  }

  public func deleteRemoteBranch(name: String, from remoteName: String) async {
    await perform { try await $0.deleteRemoteBranch(name: name, from: remoteName) }
  }

  public func worktree(for branch: Branch) -> Worktree? {
    worktrees.first { $0.branch == branch.name }
  }

  @discardableResult
  public func addWorktree(path: URL, branch: String) async -> Bool {
    await perform { try await $0.addWorktree(path: path, branch: branch) }
  }

  @discardableResult
  public func addWorktree(
    path: URL,
    remoteBranch: String,
    localBranch: String
  ) async -> Bool {
    await perform {
      try await $0.addWorktree(
        path: path,
        remoteBranch: remoteBranch,
        localBranch: localBranch
      )
    }
  }

  public func removeWorktree(
    path: URL,
    force: Bool = false,
    deleteBranch branchName: String? = nil,
    forceDeleteBranch: Bool = false,
    deleteRemoteUpstream upstream: String? = nil
  ) async {
    await perform {
      try await $0.removeWorktree(path: path, force: force)
      if let branchName {
        try await $0.deleteBranch(name: branchName, force: forceDeleteBranch)
        if let upstream,
          let (remoteName, remoteBranch) = Self.remoteBranchComponents(of: upstream)
        {
          try await $0.deleteRemoteBranch(name: remoteBranch, from: remoteName)
        }
      }
    }
  }

  /// Linked worktrees whose folders are gone.
  public var prunableWorktrees: [Worktree] { worktrees.filter(\.isPrunable) }

  public func pruneWorktrees() async {
    await perform { try await $0.pruneWorktrees() }
  }

  public func lockWorktree(_ worktree: Worktree, reason: String?) async {
    await perform { try await $0.lockWorktree(path: worktree.path, reason: reason) }
  }

  public func unlockWorktree(_ worktree: Worktree) async {
    await perform { try await $0.unlockWorktree(path: worktree.path) }
  }

  @discardableResult
  public func moveWorktree(_ worktree: Worktree, to destination: URL) async -> Bool {
    await perform { try await $0.moveWorktree(path: worktree.path, to: destination) }
  }

  public func sparseCheckoutPaths() async throws -> [String]? {
    try await gitClient.sparseCheckoutPaths()
  }

  public func setSparseCheckout(paths: [String]) async {
    guard paths.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    else {
      lastErrorMessage = SparseCheckoutError.emptyPaths.localizedDescription
      lastErrorIsFromBackgroundRead = false
      return
    }
    await perform { try await $0.setSparseCheckout(paths: paths) }
  }

  public func disableSparseCheckout() async {
    await perform { try await $0.disableSparseCheckout() }
  }

  /// Fetches older history into a shallow clone; the refresh that
  /// follows reloads History with it.
  @discardableResult
  public func deepenHistory(_ depth: HistoryDepth) async -> Bool {
    await perform { try await $0.deepenHistory(depth) }
  }

  public func fetch() async {
    await perform { try await $0.fetch() }
    await syncPullRequests(force: true)
  }

  /// Whether `backfillEstimate` can measure this repository.
  public var canEstimateBackfill: Bool {
    gitCapabilities.supportsRemoteObjectInfo && partialCloneRemote != nil
  }

  /// Counts the objects `backfill` would download and asks the promisor
  /// remote for their total size, downloading nothing.
  public func backfillEstimate() async throws -> BackfillEstimate {
    let missing = try await gitClient.missingObjectIDs()
    guard !missing.isEmpty, let remote = partialCloneRemote else {
      return BackfillEstimate(
        missingObjectCount: missing.count,
        downloadByteCount: missing.isEmpty ? 0 : nil,
        sizeUnavailableReason: nil
      )
    }
    do {
      let sizes = try await gitClient.remoteObjectSizes(of: missing, from: remote)
      return BackfillEstimate(
        missingObjectCount: missing.count,
        downloadByteCount: sizes.values.reduce(0, +),
        sizeUnavailableReason: nil
      )
    } catch {
      // Servers without the object-info capability still allow a backfill.
      return BackfillEstimate(
        missingObjectCount: missing.count,
        downloadByteCount: nil,
        sizeUnavailableReason: "“\(remote)” did not report object sizes."
      )
    }
  }

  public func backfill() async {
    await perform { try await $0.backfill() }
  }

  /// Whether "Remove Large Downloaded Blobs" applies: a partial clone on a
  /// git that supports `repack --drop-filtered`.
  public var canDropLargeBlobs: Bool {
    gitCapabilities.supportsRepackDropFiltered && partialCloneRemote != nil
  }

  public func dropLargeBlobs(largerThan byteLimit: Int) async {
    await perform { try await $0.dropLargeBlobs(largerThan: byteLimit) }
  }

  /// Pulls the current branch. The strategy defaults to the repository's
  /// config; `--autostash` follows the app-wide preference.
  public func pull(_ strategy: PullOptions.Strategy = .configured) async {
    let options = PullOptions(strategy: strategy, autostash: pullAutostash)
    await perform { try await $0.pull(options) }
  }

  public func push(force: Bool = false) async {
    await perform { try await $0.push(force: force) }
    await syncPullRequests(force: true)
  }

  public func saveStash(message: String?, includeUntracked: Bool) async {
    await perform { try await $0.saveStash(message: message, includeUntracked: includeUntracked) }
  }

  @discardableResult
  public func saveStash(_ options: StashSaveOptions) async -> Bool {
    await perform { try await $0.saveStash(options) }
  }

  public func applyStash(_ stash: Stash, pop: Bool) async {
    await perform { try await $0.applyStash(stash, pop: pop) }
  }

  public func dropStash(_ stash: Stash) async {
    await perform { try await $0.dropStash(stash) }
  }

  /// Moves the stash onto a new branch made where it was stashed.
  @discardableResult
  public func branchFromStash(_ stash: Stash, name: String) async -> Bool {
    await perform { try await $0.branchFromStash(stash, name: name) }
  }

  public func stashDiffs(_ stash: Stash) async throws -> [FileDiff] {
    try await gitClient.stashDiffs(stash)
  }

  private static func remoteBranchComponents(
    of upstream: String
  ) -> (remoteName: String, branchName: String)? {
    guard let separator = upstream.firstIndex(of: "/") else { return nil }
    let remoteName = String(upstream[..<separator])
    let branchName = String(upstream[upstream.index(after: separator)...])
    guard !remoteName.isEmpty, !branchName.isEmpty else { return nil }
    return (remoteName, branchName)
  }

  @discardableResult
  func perform(_ operation: (any GitClient) async throws -> Void) async -> Bool {
    isBusy = true
    var succeeded = false
    do {
      try await operation(gitClient)
      clearError()
      succeeded = true
    } catch {
      lastErrorMessage = error.localizedDescription
      lastErrorIsFromBackgroundRead = false
    }
    isBusy = false
    await refresh()
    return succeeded
  }
}
