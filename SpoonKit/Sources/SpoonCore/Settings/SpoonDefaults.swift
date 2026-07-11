public import Defaults

extension Defaults.Keys {
  /// Most-recently-opened first, canonical root paths.
  public static let recentRepositoryPaths = Key<[String]>("recentRepositoryPaths", default: [])

  /// Per-tool absolute path overrides, keyed by `ExternalTool.rawValue`.
  public static let toolPathOverrides = Key<[String: String]>("toolPathOverrides", default: [:])
}
