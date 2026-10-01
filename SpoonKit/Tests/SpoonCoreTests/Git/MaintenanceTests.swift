import Foundation
import Testing

@testable import SpoonCore

@Suite("Maintenance")
struct MaintenanceTests {
  private let prefix = ["-c", "color.ui=false", "-c", "core.quotePath=false"]

  @Test func countObjectsIsReadInBytes() {
    let storage = RepositoryStorage.parse(
      """
      count: 12
      size: 48
      in-pack: 3400
      packs: 2
      size-pack: 1024
      prune-packable: 0
      garbage: 1
      size-garbage: 4
      """)
    #expect(
      storage
        == RepositoryStorage(
          looseObjects: 12, looseBytes: 48 * 1024, packs: 2, packedObjects: 3400,
          packBytes: 1024 * 1024, garbageBytes: 4 * 1024))
    #expect(storage.totalBytes == (48 + 1024 + 4) * 1024)
  }

  @Test func backgroundMaintenanceMatchesThisRepositoryOnly() async throws {
    let runner = FakeCommandRunner()
    let root = URL(filePath: "/tmp/spoon-maintenance-repo")
    let client = SystemGitClient(
      repositoryRoot: root, git: URL(filePath: "/usr/bin/git"), runner: runner)
    runner.stub(
      arguments: prefix + ["config", "--global", "--get-all", "maintenance.repo"],
      stdout: "/tmp/other\n\(root.resolvingSymlinksInPath().path(percentEncoded: false))\n")
    #expect(try await client.isBackgroundMaintenanceEnabled())

    let none = FakeCommandRunner()
    none.stub(
      arguments: prefix + ["config", "--global", "--get-all", "maintenance.repo"], exitCode: 1)
    #expect(
      !(try await SystemGitClient(
        repositoryRoot: root, git: URL(filePath: "/usr/bin/git"), runner: none
      ).isBackgroundMaintenanceEnabled()))
  }
}
