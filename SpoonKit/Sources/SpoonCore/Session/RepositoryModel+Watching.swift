extension RepositoryModel {
  /// Auto-refreshes on repository changes. Self-inflicted events are
  /// suppressed while a mutation runs; `perform` refreshes afterwards.
  public func startWatching() {
    guard watchTask == nil else { return }
    let root = repository.rootURL
    watchTask = Task { [weak self] in
      for await _ in RepoWatcher.changes(under: root) {
        guard let self else { break }
        if self.isBusy || self.isRefreshing { continue }
        await self.refresh()
      }
    }
  }

  public func stopWatching() {
    watchTask?.cancel()
    watchTask = nil
  }
}
