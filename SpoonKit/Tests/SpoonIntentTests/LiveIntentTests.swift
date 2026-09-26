import AppIntentsTesting
import Foundation
import Testing

/// Drives the intent through the system App Intents runtime against the
/// registered Spoon.app build (launches the app). Opt-in:
/// SPOON_LIVE_INTENT=1 swift test --filter LiveIntent
@Suite(
  "LiveIntent",
  .enabled(if: ProcessInfo.processInfo.environment["SPOON_LIVE_INTENT"] == "1")
)
struct LiveIntentTests {
  @Test func openRecentRepositoryIsRegisteredAndRuns() async throws {
    let definitions = IntentDefinitions(bundleIdentifier: "com.spoon.app")
    let intent = definitions.intents["OpenRecentRepositoryIntent"].makeIntent()
    _ = try await intent.run()
  }
}
