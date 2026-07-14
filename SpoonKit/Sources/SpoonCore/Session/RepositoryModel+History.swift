extension RepositoryModel {
  public var historyRows: [GraphRow] { historyStore.historyRows }
  public var isLoadingHistory: Bool { historyStore.isLoadingHistory }
  public var hasMoreHistory: Bool { historyStore.hasMoreHistory }

  public func loadHistoryIfNeeded(reference: String? = nil) async {
    await historyStore.loadIfNeeded(reference: reference, hasHead: status?.headOID != nil)
    adoptHistoryError()
  }

  public func reloadHistory() async {
    await historyStore.reloadCurrent(hasHead: status?.headOID != nil)
    adoptHistoryError()
  }

  /// Reloads history against HEAD, dropping a reference that no longer
  /// resolves (e.g. a branch that was just deleted).
  func resetHistoryToHead() async {
    await historyStore.reload(reference: nil, hasHead: status?.headOID != nil)
    adoptHistoryError()
  }

  public func loadMoreHistory() async {
    await historyStore.loadMore()
    adoptHistoryError()
  }

  public func fileHistory(_ query: LogQuery) async throws -> LogPage {
    try await gitClient.log(query)
  }

  public func reflog(maxCount: Int = 500, skip: Int = 0) async throws -> [ReflogEntry] {
    try await gitClient.reflog(maxCount: maxCount, skip: skip)
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
