public import AppIntents
import Foundation
import SpoonCore

/// Opens a recently used repository by name — Spotlight / Siri surface.
public struct OpenRecentRepositoryIntent: AppIntent {
  static public let title: LocalizedStringResource = "Open Repository"
  static public let description = IntentDescription("Opens a recent git repository in Spoon.")
  static public let openAppWhenRun = true

  @Parameter(title: "Repository Name")
  public var name: String?
  
  public init() {}

  @MainActor
  public func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let appModel = AppModel.shared else {
      return .result(dialog: "Spoon is still starting up — try again.")
    }
    switch RecentRepositories.resolve(name: name, in: appModel.recentRepositories) {
    case .failure(let message):
      return .result(dialog: "\(message)")
    case .found(let repository):
      appModel.submitExternalOpenRequest(repository.rootURL)
      return .result(dialog: "Opening \(repository.name).")
    }
  }
}
