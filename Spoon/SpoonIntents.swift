import AppIntents
import SpoonIntent

/// Chains the SpoonIntent package into the app's App Intents metadata scan;
/// without this the intents defined there are invisible to Shortcuts/Siri.
extension SpoonApp: AppIntentsPackage {
  nonisolated static var includedPackages: [any AppIntentsPackage.Type] {
    [SpoonIntentPackage.self]
  }
}

struct SpoonShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenRecentRepositoryIntent(),
      phrases: [
        "Open a repository in \(.applicationName)",
        "\(.applicationName)でリポジトリを開く",
      ],
      shortTitle: "Open Repository",
      systemImageName: "arrow.trianglehead.branch"
    )
  }
}
