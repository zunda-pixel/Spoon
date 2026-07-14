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
  private var references: [String] = []
  private var excludedReferences: [String] = []

  init(gitClient: any GitClient) {
    self.gitClient = gitClient
  }

  func loadIfNeeded(
    additionalRevisions: [ObjectID],
    hiddenCommitOIDs: Set<ObjectID>,
    references: [String],
    excludedReferences: [String],
    canLoadHistory: Bool
  ) async {
    guard !isLoadingHistory else { return }
    guard
      historyRows.isEmpty || self.additionalRevisions != additionalRevisions
        || self.hiddenCommitOIDs != hiddenCommitOIDs
        || self.references != references
        || self.excludedReferences != excludedReferences
    else { return }
    await reload(
      additionalRevisions: additionalRevisions,
      hiddenCommitOIDs: hiddenCommitOIDs,
      references: references,
      excludedReferences: excludedReferences,
      canLoadHistory: canLoadHistory
    )
  }

  func reload(
    additionalRevisions: [ObjectID],
    hiddenCommitOIDs: Set<ObjectID>,
    references: [String],
    excludedReferences: [String],
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
      self.references = references
      self.excludedReferences = excludedReferences
      errorMessage = nil
      return
    }
    loadedCommits = []
    self.additionalRevisions = additionalRevisions
    self.hiddenCommitOIDs = hiddenCommitOIDs
    self.references = references
    self.excludedReferences = excludedReferences
    nextHistoryQuery = LogQuery(
      allReferences: references.isEmpty,
      additionalRevisions: additionalRevisions,
      references: references,
      excludedReferences: excludedReferences
    )
    await loadMore(replacing: true)
  }

  func loadMore() async {
    _ = await loadMore(replacing: false)
  }

  func isAncestor(_ candidate: ObjectID, of descendant: ObjectID) -> Bool {
    guard loadedCommits.contains(where: { $0.oid == candidate }) else { return false }
    var commitsByOID = Dictionary(
      loadedCommits.map { ($0.oid, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var pending = [descendant]
    var visited: Set<ObjectID> = []

    while let oid = pending.popLast() {
      guard visited.insert(oid).inserted else { continue }
      if oid == candidate { return true }
      if let commit = commitsByOID.removeValue(forKey: oid) {
        pending.append(contentsOf: commit.parents)
      }
    }
    return false
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
