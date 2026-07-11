import Foundation
import Testing

@testable import SpoonCore

@Suite("RepoWatcher")
struct RepoWatcherTests {
  private let root = URL(filePath: "/repo", directoryHint: .isDirectory)

  @Test func gitTopLevelMeansIndexAndRefs() {
    let changes = RepoWatcher.classify(["/repo/.git/"], root: root)
    #expect(changes == [.index, .refs])
  }

  @Test func refsDirectoryMeansRefs() {
    let changes = RepoWatcher.classify(["/repo/.git/refs/heads/"], root: root)
    #expect(changes == [.refs])
  }

  @Test func objectsAndLogsAreIgnored() {
    let changes = RepoWatcher.classify(
      ["/repo/.git/objects/ab/", "/repo/.git/logs/", "/repo/.git/objects/pack/"],
      root: root
    )
    #expect(changes.isEmpty)
  }

  @Test func sourceDirectoryMeansWorktree() {
    let changes = RepoWatcher.classify(["/repo/Sources/App/"], root: root)
    #expect(changes == [.worktree])
  }

  @Test func buildArtifactsAreIgnored() {
    let changes = RepoWatcher.classify(
      ["/repo/.build/debug/", "/repo/DerivedData/x/", "/repo/node_modules/y/"],
      root: root
    )
    #expect(changes.isEmpty)
  }

  @Test func pathsOutsideRootAreIgnored() {
    let changes = RepoWatcher.classify(["/elsewhere/dir/"], root: root)
    #expect(changes.isEmpty)
  }

  @Test func mixedBatchUnions() {
    let changes = RepoWatcher.classify(
      ["/repo/.git/refs/heads/", "/repo/Sources/"],
      root: root
    )
    #expect(changes == [.refs, .worktree])
  }
}
