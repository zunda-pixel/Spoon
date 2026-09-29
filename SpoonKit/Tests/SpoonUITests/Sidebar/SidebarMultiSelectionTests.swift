import SpoonCore
import Testing

@testable import SpoonUI

@MainActor
@Suite("Sidebar multi-selection")
struct SidebarMultiSelectionTests {
  @Test func extendingTheSelectionKeepsThePrimaryRow() {
    let navigation = RepositoryNavigationState()
    navigation.sidebarSelection = .branch("main")

    navigation.sidebarSelections = [.branch("main"), .branch("topic"), .tag("v1")]

    #expect(navigation.sidebarSelection == .branch("main"))
    #expect(navigation.selectedBranchNames == ["main", "topic"])
  }

  @Test func deselectingThePrimaryRowPicksAnotherSelectedRow() {
    let navigation = RepositoryNavigationState()
    navigation.sidebarSelections = [.branch("a"), .branch("b")]
    navigation.sidebarSelection = .branch("a")
    navigation.sidebarSelections = [.branch("a"), .branch("b")]

    navigation.sidebarSelections = [.branch("b")]

    #expect(navigation.sidebarSelection == .branch("b"))
  }

  @Test func settingThePrimaryRowCollapsesTheSelection() {
    let navigation = RepositoryNavigationState()
    navigation.sidebarSelections = [.branch("a"), .branch("b")]

    navigation.sidebarSelection = .history

    #expect(navigation.sidebarSelections == [.history])
    #expect(navigation.selectedBranchNames.isEmpty)
  }
}
