import Testing

@testable import SpoonUI

@MainActor
@Suite("Navigation state cache")
struct NavigationStateCacheTests {
  @Test func eachRepositoryKeepsItsOwnStateUntilRemoved() {
    let cache = NavigationStateCache()
    let main = cache.state(for: "/repo")
    main.select(.history)
    main.selectedCommitID = "abc"
    let worktree = cache.state(for: "/repo-worktree")

    #expect(worktree !== main)
    #expect(worktree.sidebarSelection == .changes)
    #expect(cache.state(for: "/repo") === main)
    #expect(cache.state(for: "/repo").selectedCommitID == "abc")

    cache.remove("/repo")
    #expect(cache.state(for: "/repo") !== main)
    #expect(cache.state(for: "/repo").selectedCommitID == nil)
  }
}
