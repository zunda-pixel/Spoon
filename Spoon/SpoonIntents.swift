import AppIntents
import Foundation
import SpoonCore

/// Opens a recently used repository by name — Spotlight / Siri surface.
struct OpenRecentRepositoryIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Repository"
  static let description = IntentDescription("Opens a recent git repository in Spoon.")
  static let openAppWhenRun = true

  @Parameter(title: "Repository Name")
  var name: String?

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let appModel = AppModel.shared else {
      return .result(dialog: "Spoon is still starting up — try again.")
    }
    let recents = appModel.recentRepositories
    guard !recents.isEmpty else {
      return .result(dialog: "No recent repositories yet.")
    }
    let repository: Repository
    if let name, !name.isEmpty {
      guard let match = recents.first(where: { $0.name.localizedCaseInsensitiveContains(name) })
      else {
        return .result(dialog: "No recent repository named \(name).")
      }
      repository = match
    } else {
      repository = recents[0]
    }
    appModel.submitExternalOpenRequest(repository.rootURL)
    return .result(dialog: "Opening \(repository.name).")
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
