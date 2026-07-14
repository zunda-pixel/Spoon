public import Foundation

extension RepositoryModel {
  public func stage(paths: [String]) async {
    await perform { try await $0.stage(paths: paths) }
  }

  public func unstage(paths: [String]) async {
    await perform { try await $0.unstage(paths: paths) }
  }

  public func discardWorkingTree(paths: [String]) async {
    await perform { try await $0.discardWorkingTree(paths: paths) }
  }

  public func deleteUntracked(paths: [String]) async {
    await perform { try await $0.deleteUntracked(paths: paths) }
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
    await perform { try await $0.commit(message: message, amend: amend) }
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

  public func merge(branch: String, options: MergeOptions = .standard) async {
    await perform { try await $0.merge(branch: branch, options: options) }
  }

  public func createTag(name: String, at target: ObjectID?, message: String?) async {
    await perform { try await $0.createTag(name: name, at: target, message: message) }
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

  public func deleteRemoteBranch(name: String, from remoteName: String) async {
    await perform { try await $0.deleteRemoteBranch(name: name, from: remoteName) }
  }

  public func worktree(for branch: Branch) -> Worktree? {
    worktrees.first { $0.branch == branch.name }
  }

  public func addWorktree(path: URL, branch: String) async {
    await perform { try await $0.addWorktree(path: path, branch: branch) }
  }

  public func addWorktree(
    path: URL,
    remoteBranch: String,
    localBranch: String
  ) async {
    await perform {
      try await $0.addWorktree(
        path: path,
        remoteBranch: remoteBranch,
        localBranch: localBranch
      )
    }
  }

  public func removeWorktree(path: URL, force: Bool = false) async {
    await perform { try await $0.removeWorktree(path: path, force: force) }
  }

  public func sparseCheckoutPaths() async throws -> [String]? {
    try await gitClient.sparseCheckoutPaths()
  }

  public func setSparseCheckout(paths: [String]) async {
    guard paths.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    else {
      lastErrorMessage = SparseCheckoutError.emptyPaths.localizedDescription
      return
    }
    await perform { try await $0.setSparseCheckout(paths: paths) }
  }

  public func disableSparseCheckout() async {
    await perform { try await $0.disableSparseCheckout() }
  }

  public func fetch() async {
    await perform { try await $0.fetch() }
    await syncPullRequests(force: true)
  }

  public func backfill() async {
    await perform { try await $0.backfill() }
  }

  public func pull() async {
    await perform { try await $0.pull() }
  }

  public func push(force: Bool = false) async {
    await perform { try await $0.push(force: force) }
    await syncPullRequests(force: true)
  }

  public func saveStash(message: String?, includeUntracked: Bool) async {
    await perform { try await $0.saveStash(message: message, includeUntracked: includeUntracked) }
  }

  public func applyStash(_ stash: Stash, pop: Bool) async {
    await perform { try await $0.applyStash(stash, pop: pop) }
  }

  public func dropStash(_ stash: Stash) async {
    await perform { try await $0.dropStash(stash) }
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
      lastErrorMessage = nil
      succeeded = true
    } catch {
      lastErrorMessage = error.localizedDescription
    }
    isBusy = false
    await refresh()
    return succeeded
  }
}
