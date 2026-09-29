extension RepositoryModel {
  /// Auto-refreshes on repository changes. Self-inflicted events are
  /// suppressed while a mutation runs; `perform` refreshes afterwards.
  public func startWatching() {
    guard watchTask == nil else { return }
    let root = repository.rootURL
    let gitClient = gitClient
    watchTask = Task { [weak self] in
      // A linked worktree's HEAD, index, and refs live outside its root.
      let layout =
        if let paths = try? await gitClient.repositoryPaths() {
          RepoWatcher.Layout(root: root, paths: paths)
        } else {
          RepoWatcher.Layout(root: root)
        }
      for await _ in RepoWatcher.changes(in: layout) {
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
