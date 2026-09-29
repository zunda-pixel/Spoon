public import Defaults

extension Defaults.Keys {
  /// Most-recently-opened first, canonical root paths.
  public static let recentRepositoryPaths = Key<[String]>("recentRepositoryPaths", default: [])

  /// Per-tool absolute path overrides, keyed by `ExternalTool.rawValue`.
  public static let toolPathOverrides = Key<[String: String]>("toolPathOverrides", default: [:])

  /// History references selected for inclusion, keyed by repository ID.
  public static let historyFocusedReferenceIDs = Key<[String: [String]]>(
    "historyFocusedReferenceIDs",
    default: [:]
  )

  /// History references excluded from the unified history, keyed by repository ID.
  public static let historyHiddenReferenceIDs = Key<[String: [String]]>(
    "historyHiddenReferenceIDs",
    default: [:]
  )

  /// Stash local changes around every pull (`git pull --autostash`).
  public static let pullAutostash = Key<Bool>("pullAutostash", default: false)

  /// Check GitHub for a newer release when the app launches.
  public static let automaticallyCheckForUpdates = Key<Bool>(
    "automaticallyCheckForUpdates",
    default: true
  )

  /// Release tag the user chose to skip; not offered again at launch.
  public static let skippedUpdateVersion = Key<String?>("skippedUpdateVersion", default: nil)
}
