import Defaults
import Foundation
import SpoonCore

/// Shared recents lookup for App Intents.
enum RecentRepositories {
  /// The persisted recents, newest first — readable without an AppModel.
  static func all() -> [Repository] {
    Defaults[.recentRepositoryPaths].map {
      Repository(rootURL: URL(filePath: $0, directoryHint: .isDirectory))
    }
  }

  enum Resolution {
    case found(Repository)
    /// Dialog text explaining why nothing matched.
    case failure(String)
  }

  /// Case-insensitive name match; a nil/empty name means the most recent.
  static func resolve(name: String?, in recents: [Repository]) -> Resolution {
    guard !recents.isEmpty else {
      return .failure("No recent repositories yet.")
    }
    guard let name, !name.isEmpty else {
      return .found(recents[0])
    }
    guard let match = recents.first(where: { $0.name.localizedCaseInsensitiveContains(name) })
    else {
      return .failure("No recent repository named \(name).")
    }
    return .found(match)
  }
}
