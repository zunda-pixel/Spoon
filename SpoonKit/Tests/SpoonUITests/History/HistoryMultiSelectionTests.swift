import Testing

@testable import SpoonUI

@MainActor
@Suite("History multi-selection")
struct HistoryMultiSelectionTests {
  @Test func extendingKeepsTheDetailOnThePrimaryCommit() {
    let navigation = RepositoryNavigationState()
    navigation.selectedCommitID = "bbbb"

    navigation.selectedCommitIDs = ["aaaa", "bbbb", "cccc"]
    #expect(navigation.selectedCommitID == "bbbb")

    navigation.selectedCommitIDs = ["aaaa", "cccc"]
    #expect(navigation.selectedCommitID == "aaaa")

    navigation.selectedCommitID = "dddd"
    #expect(navigation.selectedCommitIDs == ["dddd"])
  }
}
