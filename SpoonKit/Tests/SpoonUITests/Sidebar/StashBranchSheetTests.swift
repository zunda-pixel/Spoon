import Testing

@testable import SpoonUI

@MainActor
@Suite("Stash branch sheet")
struct StashBranchSheetTests {
  @Test func suggestsANameFromACustomStashMessageOnly() {
    #expect(
      StashBranchSheet.suggestedName(for: "On main: Try a longer greeting!")
        == "try-a-longer-greeting")
    #expect(
      StashBranchSheet.suggestedName(for: "On feature/x: Fix the #42 crash, then more words here")
        == "fix-the-42-crash-then-more")
    #expect(StashBranchSheet.suggestedName(for: "WIP on main: 4ae2b1b Add login").isEmpty)
  }
}
