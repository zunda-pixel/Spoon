extension RepositoryModel {
  public var historyRows: [GraphRow] { historyStore.historyRows }
  public var isLoadingHistory: Bool { historyStore.isLoadingHistory }
  public var hasMoreHistory: Bool { historyStore.hasMoreHistory }

  /// Loads the single history graph spanning every repository reference.
  public func loadHistoryIfNeeded() async {
    await historyStore.loadIfNeeded(
      additionalRevisions: detachedWorktreeHeads,
      hiddenCommitOIDs: stashHelperCommitOIDs,
      canLoadHistory: canLoadUnifiedHistory
    )
    adoptHistoryError()
  }

  public func reloadHistory() async {
    await historyStore.reload(
      additionalRevisions: detachedWorktreeHeads,
      hiddenCommitOIDs: stashHelperCommitOIDs,
      canLoadHistory: canLoadUnifiedHistory
    )
    adoptHistoryError()
  }

  /// Ensures a commit from the unified graph has been paged into memory.
  public func ensureCommitLoaded(_ oid: ObjectID) async -> Bool {
    let loaded = await historyStore.ensureCommitLoaded(oid)
    adoptHistoryError()
    return loaded
  }

  public func loadMoreHistory() async {
    await historyStore.loadMore()
    adoptHistoryError()
  }

  /// Whether reverting this commit is meaningful on the currently checked-out history.
  public func canRevert(_ oid: ObjectID) -> Bool {
    guard let headOID = status?.headOID else { return false }
    return historyStore.isAncestor(oid, of: headOID)
  }

  /// Temporary source-compatible bridge while History UI still passes a ref.
  /// A branch selection no longer changes the history walk.
  public func loadHistoryIfNeeded(reference _: String?) async {
    await loadHistoryIfNeeded()
  }

  public func fileHistory(_ query: LogQuery) async throws -> LogPage {
    try await gitClient.log(query)
  }

  public func reflog(maxCount: Int = 500, skip: Int = 0) async throws -> [ReflogEntry] {
    try await gitClient.reflog(maxCount: maxCount, skip: skip)
  }

  private var detachedWorktreeHeads: [ObjectID] {
    var seen: Set<ObjectID> = []
    return worktrees.compactMap { worktree in
      guard worktree.branch == nil, let oid = worktree.headOID, seen.insert(oid).inserted else {
        return nil
      }
      return oid
    }
  }

  private var canLoadUnifiedHistory: Bool {
    status?.headOID != nil
      || !branches.isEmpty
      || remoteBranchesByRemote.values.contains(where: { !$0.isEmpty })
      || !tags.isEmpty
      || !stashes.isEmpty
      || !detachedWorktreeHeads.isEmpty
  }

  private var stashHelperCommitOIDs: Set<ObjectID> {
    Set(stashes.flatMap(\.helperCommitOIDs))
  }

  private func adoptHistoryError() {
    if let message = historyStore.errorMessage {
      lastErrorMessage = message
      lastErrorIsFromBackgroundRead = true
    } else if lastErrorIsFromBackgroundRead {
      // Only clear errors background reads produced; a mutation error must
      // survive the history reload that follows the failed operation.
      clearError()
    }
  }
}
