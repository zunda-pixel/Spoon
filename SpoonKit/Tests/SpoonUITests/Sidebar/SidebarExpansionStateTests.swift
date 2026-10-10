import Testing

@testable import SpoonUI

@MainActor
@Suite("Sidebar expansion")
struct SidebarExpansionStateTests {
  @Test func revealingAnotherBranchKeepsOpenFolders() {
    let expansion = SidebarExpansionState()
    expansion.revealBranch(named: "a/b")

    expansion.revealBranch(named: "d/e")

    #expect(expansion.branchFolderPaths == ["a", "d"])
  }

  @Test func revealingABranchOpensOnlyItsOwnFolders() {
    let expansion = SidebarExpansionState()
    expansion.revealBranch(named: "a/b")
    expansion.branchFolderPaths.remove("a")

    expansion.revealBranch(named: "team/d/e")

    #expect(expansion.branchFolderPaths == ["team", "team/d"])
  }
}
