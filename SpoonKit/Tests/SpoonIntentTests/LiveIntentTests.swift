#if canImport(AppIntentsTesting)
import AppIntentsTesting
import Foundation
import Testing

/// Drives the intent through the system App Intents runtime against the
/// registered Spoon.app build (launches the app). Opt-in:
/// SPOON_LIVE_INTENT=1 swift test --filter LiveIntent
///
/// Known limitation (macOS 27.0 beta 26A5378j / Xcode 27A5218g): the testing
/// transport is refused for package test bundles — `run()` throws
/// transportCancelled under both `swift test` and `xcodebuild test`. The
/// harness appears to require an app-hosted test bundle. Static metadata was
/// verified instead: Spoon.app/Contents/Resources/Metadata.appintents lists
/// SpoonIntent.OpenRecentRepositoryIntent and the SpoonShortcuts phrases.
@Suite(
  "LiveIntent",
  .enabled(if: ProcessInfo.processInfo.environment["SPOON_LIVE_INTENT"] == "1")
)
struct LiveIntentTests {
  @Test func openRecentRepositoryIsRegisteredAndRuns() async throws {
    guard #available(macOS 27.0, *) else { return }
    let definitions = IntentDefinitions(bundleIdentifier: "com.spoon.app")
    let intent = definitions.intents["OpenRecentRepositoryIntent"].makeIntent()
    _ = try await intent.run()
  }
}
#endif
