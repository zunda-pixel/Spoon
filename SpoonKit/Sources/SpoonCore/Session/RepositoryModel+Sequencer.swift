extension RepositoryModel {
  public var isSequencing: Bool { sequencerState != nil }

  public func rebasePlan(from commit: Commit) async throws -> RebasePlan {
    guard sequencerState == nil else { throw RebaseSetupError.sequencerActive }
    guard let status else { throw RebaseSetupError.workingTreeNotClean }
    guard status.headBranch != nil else { throw RebaseSetupError.detachedHead }
    guard
      status.stagedEntries.isEmpty,
      status.unstagedEntries.isEmpty,
      status.conflictedEntries.isEmpty
    else { throw RebaseSetupError.workingTreeNotClean }

    let baseOID = commit.parents.first
    let reference = baseOID.map { "\($0.rawValue)..HEAD" } ?? "HEAD"
    let page = try await gitClient.log(LogQuery(reference: reference, maxCount: 1000))
    guard !page.hasMore else { throw RebaseSetupError.rangeTooLarge }
    guard !page.commits.contains(where: \.isMerge) else { throw RebaseSetupError.mergeInRange }
    return RebasePlan(
      steps: page.commits.reversed().map { RebaseStep(action: .pick, commit: $0) },
      baseOID: baseOID
    )
  }

  @discardableResult
  public func interactiveRebase(_ plan: RebasePlan) async -> Bool {
    await perform { try await $0.interactiveRebase(plan) }
  }

  public func cherryPick(_ oid: ObjectID) async {
    await perform { try await $0.cherryPick(oid) }
  }

  public func revert(_ oid: ObjectID) async {
    await perform { try await $0.revert(oid) }
  }

  /// Whether `git history drop` can remove this commit.
  public func canDropCommit(_ commit: Commit) -> Bool {
    gitCapabilities.supportsHistoryDrop && !commit.isMerge && !commit.parents.isEmpty
  }

  /// The branches `dropCommit` would rewrite, or git's reason for refusing.
  public func previewDropCommit(_ oid: ObjectID) async throws -> [RefUpdate] {
    try await gitClient.dropCommit(oid, dryRun: true)
  }

  @discardableResult
  public func dropCommit(_ oid: ObjectID) async -> Bool {
    await perform { try await $0.dropCommit(oid, dryRun: false) }
  }

  /// Whether `git history reword` can edit this commit's message.
  public func canRewordCommit(_ commit: Commit) -> Bool {
    gitCapabilities.supportsHistoryReword && !commit.isMerge
  }

  @discardableResult
  public func rewordCommit(_ oid: ObjectID, message: String) async -> Bool {
    await perform { try await $0.rewordCommit(oid, message: message) }
  }

  /// Whether the staged changes can be folded into this commit with
  /// `git history fixup`.
  public func canFixupCommit(_ commit: Commit) -> Bool {
    gitCapabilities.supportsHistoryFixup && !commit.isMerge
      && status?.stagedEntries.isEmpty == false
  }

  /// The branches `fixupCommit` would rewrite, or git's reason for refusing.
  public func previewFixupCommit(_ oid: ObjectID) async throws -> [RefUpdate] {
    try await gitClient.fixupCommit(oid, dryRun: true)
  }

  @discardableResult
  public func fixupCommit(_ oid: ObjectID) async -> Bool {
    await perform { try await $0.fixupCommit(oid, dryRun: false) }
  }

  /// Whether `branch` can be rebased onto the checked-out commit with
  /// `git replay`: it must not be checked out anywhere, since replay never
  /// updates a worktree.
  public func canReplayBranchOntoHead(_ branch: Branch) -> Bool {
    gitCapabilities.supportsReplayLinearize
      && status?.headOID != nil
      && !branch.isCurrent
      && worktree(for: branch) == nil
  }

  /// Commits of `branch` that replaying onto HEAD would rewrite, newest first.
  public func commitsToReplay(_ branch: Branch) async throws -> LogPage {
    guard let head = status?.headOID else { return LogPage(commits: [], hasMore: false) }
    return try await gitClient.log(
      LogQuery(reference: "\(head.rawValue)..refs/heads/\(branch.name)", maxCount: 1000)
    )
  }

  @discardableResult
  public func replayBranchOntoHead(_ branch: Branch, linearize: Bool) async -> Bool {
    guard let head = status?.headOID else { return false }
    return await perform {
      try await $0.replayBranch(branch.name, onto: head, linearize: linearize)
    }
  }

  /// Whether the staged changes can be recorded as a fixup for `commit`.
  public func canCommitFixup(for commit: Commit) -> Bool {
    !commit.isMerge && !isSequencing && status?.stagedEntries.isEmpty == false
      && canRevert(commit.oid)
  }

  @discardableResult
  public func commitFixup(for commit: Commit) async -> Bool {
    await perform { try await $0.commitFixup(for: commit.oid) }
  }

  /// The fixup commits on the current branch that autosquash would fold,
  /// and the commit it would rebase onto: where the branch forked from its
  /// upstream, else from the default branch.
  public func autosquashPlan() async throws -> AutosquashPlan {
    guard let head = status?.headOID, let branch = currentBranch else {
      throw RebaseSetupError.detachedHead
    }
    let baseReference: String
    if let upstream = existingRemoteUpstream(of: branch) {
      baseReference = upstream
    } else {
      baseReference = try await gitClient.defaultBranch()
    }
    let base = try await gitClient.mergeBase(baseReference, head.rawValue)
    let page = try await gitClient.log(
      LogQuery(reference: "\(base.rawValue)..\(head.rawValue)", maxCount: 1000))
    return AutosquashPlan(
      base: base,
      baseReference: baseReference,
      fixups: page.commits.filter(AutosquashPlan.isFixup)
    )
  }

  @discardableResult
  public func autosquash(_ plan: AutosquashPlan) async -> Bool {
    await perform { try await $0.autosquash(onto: plan.base) }
  }

  /// Cherry-picks `commits` onto HEAD oldest first, whatever order they
  /// were selected in, so each applies on top of the one it followed.
  /// A merge commit brings the changes it made to its first parent.
  public func cherryPick(_ commits: [Commit]) async {
    let oids = historyOrder(commits).reversed().map(\.oid)
    let options = CherryPickOptions(mainline: Self.mainline(for: commits))
    await perform { try await $0.cherryPick(Array(oids), options: options) }
  }

  /// Reverts `commits` newest first, so later changes are undone before the
  /// ones they build on. A merge commit is undone back to its first parent.
  public func revert(_ commits: [Commit]) async {
    let oids = historyOrder(commits).map(\.oid)
    let options = RevertOptions(mainline: Self.mainline(for: commits))
    await perform { try await $0.revert(oids, options: options) }
  }

  /// git refuses a merge commit without `--mainline`; the first parent is
  /// the branch it was merged into, which is what users almost always mean.
  private static func mainline(for commits: [Commit]) -> Int? {
    commits.contains(where: \.isMerge) ? 1 : nil
  }

  /// `commits` in the history list's newest-first order.
  private func historyOrder(_ commits: [Commit]) -> [Commit] {
    let position = Dictionary(
      historyRows.enumerated().map { ($1.commit.oid, $0) }, uniquingKeysWith: { first, _ in first })
    return commits.sorted { (position[$0.oid] ?? .max) < (position[$1.oid] ?? .max) }
  }

  public func continueSequencer() async {
    guard let kind = sequencerState?.kind else { return }
    await perform { try await $0.continueSequencer(kind) }
  }

  public func skipSequencer() async {
    guard let kind = sequencerState?.kind, kind != .merge else { return }
    await perform { try await $0.skipSequencer(kind) }
  }

  public func abortSequencer() async {
    guard let kind = sequencerState?.kind else { return }
    await perform { try await $0.abortSequencer(kind) }
  }
}
