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
  private(set) var loadedReference: String?

  init(gitClient: any GitClient) {
    self.gitClient = gitClient
  }

  func loadIfNeeded(reference: String?, hasHead: Bool) async {
    guard !isLoadingHistory else { return }
    guard historyRows.isEmpty || loadedReference != reference else { return }
    await reload(reference: reference, hasHead: hasHead)
  }

  func reloadCurrent(hasHead: Bool) async {
    await reload(reference: loadedReference, hasHead: hasHead)
  }

  func reload(reference: String?, hasHead: Bool) async {
    guard hasHead else {
      historyRows = []
      loadedCommits = []
      hasMoreHistory = false
      nextHistoryQuery = nil
      loadedReference = reference
      errorMessage = nil
      return
    }
    loadedCommits = []
    loadedReference = reference
    nextHistoryQuery = LogQuery(reference: reference)
    await loadMore(replacing: true)
  }

  func loadMore() async {
    await loadMore(replacing: false)
  }

  private func loadMore(replacing: Bool) async {
    guard let query = nextHistoryQuery, !isLoadingHistory else { return }
    isLoadingHistory = true
    defer { isLoadingHistory = false }
    do {
      let page = try await gitClient.log(query)
      loadedCommits.append(contentsOf: page.commits)
      hasMoreHistory = page.hasMore
      nextHistoryQuery = page.hasMore ? query.next() : nil
      historyRows = CommitGraphLayout.assignLanes(loadedCommits)
      errorMessage = nil
    } catch {
      if replacing {
        historyRows = []
      }
      errorMessage = error.localizedDescription
    }
  }
}
