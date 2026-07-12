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
