public import MemberwiseInit

/// How diffs are computed for display.
@MemberwiseInit(.public)
public struct DiffOptions: Sendable, Hashable {
  /// Hide changes that only add, remove, or alter whitespace (`-w`). The
  /// resulting hunks no longer match the file byte for byte, so they cannot
  /// be staged or discarded.
  public var ignoresWhitespace: Bool = false

  public static let standard = DiffOptions()

  var arguments: [String] {
    ignoresWhitespace ? ["--ignore-all-space"] : []
  }
}
