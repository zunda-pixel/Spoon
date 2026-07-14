import Foundation
import Testing

@testable import SpoonCore

@MainActor
@Suite("AppModel")
struct AppModelTests {
  @Test func recentsKeepOnlyNewestWorktreeForEachRepository() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "spoon-recents-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let main = root.appending(path: "main", directoryHint: .isDirectory)
    let commonGitDirectory = main.appending(path: ".git", directoryHint: .isDirectory)
    let worktreeAdmin = commonGitDirectory.appending(
      path: "worktrees/topic",
      directoryHint: .isDirectory
    )
    let linked = root.appending(path: "topic", directoryHint: .isDirectory)
    let separate = root.appending(path: "separate", directoryHint: .isDirectory)

    try FileManager.default.createDirectory(
      at: worktreeAdmin,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: linked,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: separate.appending(path: ".git", directoryHint: .isDirectory),
      withIntermediateDirectories: true
    )
    try "gitdir: \(worktreeAdmin.path)\n".write(
      to: linked.appending(path: ".git"),
      atomically: true,
      encoding: .utf8
    )
    try "../..\n".write(
      to: worktreeAdmin.appending(path: "commondir"),
      atomically: true,
      encoding: .utf8
    )

    let mainRepository = Repository(rootURL: main)
    let linkedRepository = Repository(rootURL: linked)
    let separateRepository = Repository(rootURL: separate)

    #expect(
      AppModel.recentGroupID(for: mainRepository)
        == AppModel.recentGroupID(for: linkedRepository)
    )
    #expect(
      AppModel.compactRecents([
        linkedRepository,
        mainRepository,
        separateRepository,
      ]) == [
        linkedRepository,
        separateRepository,
      ]
    )
  }
}
