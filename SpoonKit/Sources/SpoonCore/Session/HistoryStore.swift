import Foundation
import Observation

/// Owns repository history loading and pagination independently of the repository facade.
@MainActor
@Observable
final class HistoryStore {
  private(set) var historyRows: [GraphRow] = []
  private(set) var isLoadingHistory = false
  private(set) var hasMoreHistory = false
  private(set) var errorMessage: String?

  private let gitClient: any GitClient
  private var loadedCommits: [Commit] = []
  private var nextHistoryQuery: LogQuery?
  private var additionalRevisions: [ObjectID] = []
  private var hiddenCommitOIDs: Set<ObjectID> = []

  init(gitClient: any GitClient) {
    self.gitClient = gitClient
  }

  func loadIfNeeded(
    additionalRevisions: [ObjectID],
    hiddenCommitOIDs: Set<ObjectID>,
    canLoadHistory: Bool
  ) async {
    guard !isLoadingHistory else { return }
    guard
      historyRows.isEmpty || self.additionalRevisions != additionalRevisions
        || self.hiddenCommitOIDs != hiddenCommitOIDs
    else { return }
    await reload(
      additionalRevisions: additionalRevisions,
      hiddenCommitOIDs: hiddenCommitOIDs,
      canLoadHistory: canLoadHistory
    )
  }

  func reload(
    additionalRevisions: [ObjectID],
    hiddenCommitOIDs: Set<ObjectID>,
    canLoadHistory: Bool
  ) async {
    guard await waitUntilIdle() else { return }
    guard canLoadHistory else {
      historyRows = []
      loadedCommits = []
      hasMoreHistory = false
      nextHistoryQuery = nil
      self.additionalRevisions = additionalRevisions
      self.hiddenCommitOIDs = hiddenCommitOIDs
      errorMessage = nil
      return
    }
    loadedCommits = []
    self.additionalRevisions = additionalRevisions
    self.hiddenCommitOIDs = hiddenCommitOIDs
    nextHistoryQuery = LogQuery(
      allReferences: true,
      additionalRevisions: additionalRevisions
    )
    await loadMore(replacing: true)
  }

  func loadMore() async {
    _ = await loadMore(replacing: false)
  }

  /// Loads subsequent pages until `oid` is available or the unified walk ends.
  /// Cooperates with an in-flight background page load instead of racing it.
  func ensureCommitLoaded(_ oid: ObjectID) async -> Bool {
    while true {
      guard await waitUntilIdle() else { return false }
      if loadedCommits.contains(where: { $0.oid == oid }) {
        return true
      }
      guard hasMoreHistory else { return false }
      let previousCount = loadedCommits.count
      guard await loadMore(replacing: false) else { return false }
      if loadedCommits.contains(where: { $0.oid == oid }) {
        return true
      }
      // A malformed page that claims more data without adding commits must not
      // turn focus navigation into an infinite loop.
      guard loadedCommits.count > previousCount else { return false }
    }
  }

  private func waitUntilIdle() async -> Bool {
    while isLoadingHistory {
      do {
        try await Task.sleep(for: .milliseconds(20))
      } catch {
        return false
      }
    }
    return !Task.isCancelled
  }

  @discardableResult
  private func loadMore(replacing: Bool) async -> Bool {
    guard nextHistoryQuery != nil, !isLoadingHistory else { return false }
    isLoadingHistory = true
    defer { isLoadingHistory = false }
    do {
      while let query = nextHistoryQuery {
        let page = try await gitClient.log(query)
        guard !Task.isCancelled else { return false }
        hasMoreHistory = page.hasMore
        nextHistoryQuery = page.hasMore ? query.next() : nil
        let visibleCommits = page.commits.compactMap { commit -> Commit? in
          guard !hiddenCommitOIDs.contains(commit.oid) else { return nil }
          var commit = commit
          commit.parents.removeAll(where: hiddenCommitOIDs.contains)
          return commit
        }
        loadedCommits.append(contentsOf: visibleCommits)
        if !visibleCommits.isEmpty || !page.hasMore {
          historyRows = CommitGraphLayout.assignLanes(loadedCommits)
          errorMessage = nil
          return true
        }
      }
      return false
    } catch is CancellationError {
      return false
    } catch {
      if replacing {
        historyRows = []
      }
      errorMessage = error.localizedDescription
      return false
    }
  }
}
