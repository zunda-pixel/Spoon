import Defaults
import Foundation
import SpoonCore
import SpoonIntent
import Testing

// Serialized: these tests (including the extension in
// StashChangesIntentTests.swift) share the process-wide Defaults recents key.
@Suite(.serialized)
@MainActor
struct OpenRecentRepositoryIntentTests {
  @Test func performRoutesThroughAppModelRecents() async throws {
    let saved = Defaults[.recentRepositoryPaths]
    defer { Defaults[.recentRepositoryPaths] = saved }

    // Without a live AppModel the intent must degrade gracefully.
    #expect(AppModel.shared == nil)
    _ = try await OpenRecentRepositoryIntent().perform()

    Defaults[.recentRepositoryPaths] = ["/tmp/spoon-intent-fixture"]
    let appModel = AppModel()
    #expect(AppModel.shared === appModel)

    // No name: opens the most recent repository.
    _ = try await OpenRecentRepositoryIntent().perform()
    #expect(appModel.takeExternalOpenRequest()?.lastPathComponent == "spoon-intent-fixture")

    // Name that matches nothing: no open request.
    let miss = OpenRecentRepositoryIntent()
    miss.name = "no-such-repository"
    _ = try await miss.perform()
    #expect(appModel.takeExternalOpenRequest() == nil)

    // Case-insensitive substring match on the folder name.
    let hit = OpenRecentRepositoryIntent()
    hit.name = "FIXTURE"
    _ = try await hit.perform()
    #expect(appModel.takeExternalOpenRequest()?.lastPathComponent == "spoon-intent-fixture")
  }
}
