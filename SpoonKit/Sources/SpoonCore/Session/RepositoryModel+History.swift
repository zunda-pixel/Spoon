import Defaults
import Foundation

extension RepositoryModel {
  /// The commits that changed `lines` of `path` at HEAD, newest first.
  public func lineHistory(path: String, lines: ClosedRange<Int>, limit: Int = 200) async throws
    -> [LineHistoryEntry]
  {
    try await gitClient.lineHistory(path: path, lines: lines, limit: limit)
  }

  /// Whether `path` differs from HEAD, so its working-tree line numbers
  /// may not match the ones `lineHistory` reads.
  public func hasUncommittedChanges(at path: String) -> Bool {
    status?.entries.contains { $0.path == path && !$0.isIgnored } ?? false
  }

  /// Lines matching `query` in the working tree or a revision.
  public func searchCode(_ query: CodeSearchQuery, limit: Int = 2_000) async throws
    -> CodeSearchResult
  {
    try await gitClient.searchCode(query, limit: limit)
  }

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

  /// Focuses the history on `base` and every local branch whose configured
  /// upstream is `base` (`git branch --forked`).
  public func focusHistoryOnBranches(forkedFrom base: HistoryReferenceFilterID) async {
    let names: [String]
    do {
      names = try await gitClient.branchNames(forkedFrom: base.gitReference)
    } catch {
      lastErrorMessage = error.localizedDescription
      lastErrorIsFromBackgroundRead = false
      return
    }
    let ids = Set([base.id] + names.map { HistoryReferenceFilterID.localBranch($0).id })
    focusedHistoryReferenceIDs = ids
    hiddenHistoryReferenceIDs.subtract(ids)
    persistHistoryReferenceFilters()
    await reloadHistory()
  }

  /// Shows exactly these references in the history.
  public func focusHistory(onReferences references: [HistoryReferenceFilterID]) async {
    let ids = Set(references.map(\.id))
    focusedHistoryReferenceIDs = ids
    hiddenHistoryReferenceIDs.subtract(ids)
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
      additionalRevisions: [],
      hiddenCommitOIDs: stashHelperCommitOIDs,
      references: historyReferenceURLs(for: effectiveFocusedHistoryReferenceIDs),
      excludedReferences: historyReferenceURLs(for: effectiveHiddenHistoryReferenceIDs),
      canLoadHistory: canLoadUnifiedHistory
    )
    adoptHistoryError()
  }

  public func reloadHistory() async {
    await historyStore.reload(
      additionalRevisions: [],
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

  public func blame(path: String, at revision: ObjectID? = nil) async throws -> [BlameLine] {
    try await gitClient.blame(path: path, at: revision)
  }

  /// One page of commits, across every reference, that match `search`.
  public func searchHistory(_ search: HistorySearch, skip: Int = 0) async throws -> LogPage {
    var page = try await gitClient.log(
      LogQuery(maxCount: 200, skip: skip, allReferences: true, search: search)
    )
    // `--all` reaches stash helper commits, which the history graph hides too.
    let hidden = stashHelperCommitOIDs
    page.commits.removeAll { hidden.contains($0.oid) }
    return page
  }

  /// Pairs the commits of `branch` with those of an earlier version of it
  /// (`git range-diff`). Both ranges start where each version forked from
  /// the branch it builds on (its upstream, else the default branch), so a
  /// rebase onto a newer base shows only the branch's own commits.
  public func compareBranchVersions(
    _ branch: Branch,
    with baseline: BranchVersionBaseline
  ) async throws -> [RangeDiffEntry] {
    let oldTip: ObjectID
    let baseReference: String
    switch baseline {
    case .previousPosition:
      guard let previous = try await gitClient.previousTip(of: "refs/heads/\(branch.name)") else {
        throw BranchVersionComparisonError.noPreviousPosition(branch: branch.name)
      }
      oldTip = previous
      if let upstream = existingRemoteUpstream(of: branch) {
        baseReference = upstream
      } else {
        baseReference = try await gitClient.defaultBranch()
      }
    case .upstream:
      guard
        let upstream = existingRemoteUpstream(of: branch),
        let remoteName = branch.upstreamRemoteName,
        let upstreamTip = remoteBranchesByRemote[remoteName]?.first(where: { $0.name == upstream })?
          .tip
      else {
        throw BranchVersionComparisonError.noUpstream(branch: branch.name)
      }
      oldTip = upstreamTip
      baseReference = try await gitClient.defaultBranch()
    }
    async let oldBase = gitClient.mergeBase(baseReference, oldTip.rawValue)
    async let newBase = gitClient.mergeBase(baseReference, branch.tip.rawValue)
    return try await gitClient.rangeDiff(
      oldBase: oldBase, oldTip: oldTip, newBase: newBase, newTip: branch.tip
    )
  }

  public func fileHistory(_ query: LogQuery) async throws -> LogPage {
    try await gitClient.log(query)
  }

  public func reflog(maxCount: Int = 500, skip: Int = 0) async throws -> [ReflogEntry] {
    try await gitClient.reflog(maxCount: maxCount, skip: skip)
  }

  private var canLoadUnifiedHistory: Bool {
    status?.headOID != nil
      || !branches.isEmpty
      || remoteBranchesByRemote.values.contains(where: { !$0.isEmpty })
      || !tags.isEmpty
      || !stashes.isEmpty
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
