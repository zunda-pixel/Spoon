import Defaults

extension RepositoryModel {
  public var historyRows: [GraphRow] { historyStore.historyRows }
  public var isLoadingHistory: Bool { historyStore.isLoadingHistory }
  public var hasMoreHistory: Bool { historyStore.hasMoreHistory }

  public func isHistoryReferenceFocused(_ id: String) -> Bool {
    focusedHistoryReferenceIDs.contains(id)
  }

  public func isHistoryReferenceHidden(_ id: String) -> Bool {
    hiddenHistoryReferenceIDs.contains(id)
  }

  /// The reference IDs whose labels should remain visible in the history.
  /// `nil` means that all references should be shown.
  public var visibleHistoryReferenceIDs: Set<String>? {
    if !effectiveFocusedHistoryReferenceIDs.isEmpty {
      return effectiveFocusedHistoryReferenceIDs
    }
    guard !effectiveHiddenHistoryReferenceIDs.isEmpty else { return nil }
    return allHistoryReferenceIDs.subtracting(effectiveHiddenHistoryReferenceIDs)
  }

  public func toggleHistoryFocus(_ id: String) async {
    if focusedHistoryReferenceIDs.contains(id) {
      focusedHistoryReferenceIDs.remove(id)
    } else {
      focusedHistoryReferenceIDs.insert(id)
      hiddenHistoryReferenceIDs.remove(id)
    }
    persistHistoryReferenceFilters()
    await reloadHistory()
  }

  public func toggleHistoryHidden(_ id: String) async {
    if hiddenHistoryReferenceIDs.contains(id) {
      hiddenHistoryReferenceIDs.remove(id)
    } else {
      hiddenHistoryReferenceIDs.insert(id)
      focusedHistoryReferenceIDs.removeAll()
    }
    persistHistoryReferenceFilters()
    await reloadHistory()
  }

  /// Loads the single history graph spanning every repository reference.
  public func loadHistoryIfNeeded() async {
    await historyStore.loadIfNeeded(
      additionalRevisions: detachedWorktreeHeads,
      hiddenCommitOIDs: stashHelperCommitOIDs,
      references: historyReferenceURLs(for: effectiveFocusedHistoryReferenceIDs),
      excludedReferences: historyReferenceURLs(for: effectiveHiddenHistoryReferenceIDs),
      canLoadHistory: canLoadUnifiedHistory
    )
    adoptHistoryError()
  }

  public func reloadHistory() async {
    await historyStore.reload(
      additionalRevisions: detachedWorktreeHeads,
      hiddenCommitOIDs: stashHelperCommitOIDs,
      references: historyReferenceURLs(for: effectiveFocusedHistoryReferenceIDs),
      excludedReferences: historyReferenceURLs(for: effectiveHiddenHistoryReferenceIDs),
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

  private func historyReferenceURLs(for ids: Set<String>) -> [String] {
    ids.compactMap { HistoryReferenceFilterID(id: $0)?.gitReference }.sorted()
  }

  private var allHistoryReferenceIDs: Set<String> {
    var ids = Set(branches.map { HistoryReferenceFilterID.localBranch($0.name).id })
    for (remote, branches) in remoteBranchesByRemote {
      ids.formUnion(branches.map {
        HistoryReferenceFilterID.remoteBranch(remote: remote, name: $0.name).id
      })
    }
    ids.formUnion(tags.map { HistoryReferenceFilterID.tag($0.name).id })
    return ids
  }

  private var effectiveFocusedHistoryReferenceIDs: Set<String> {
    focusedHistoryReferenceIDs.intersection(allHistoryReferenceIDs)
  }

  private var effectiveHiddenHistoryReferenceIDs: Set<String> {
    hiddenHistoryReferenceIDs.intersection(allHistoryReferenceIDs)
  }

  private func persistHistoryReferenceFilters() {
    var focused = Defaults[.historyFocusedReferenceIDs]
    focused[repository.id] = focusedHistoryReferenceIDs.sorted()
    Defaults[.historyFocusedReferenceIDs] = focused

    var hidden = Defaults[.historyHiddenReferenceIDs]
    hidden[repository.id] = hiddenHistoryReferenceIDs.sorted()
    Defaults[.historyHiddenReferenceIDs] = hidden
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
