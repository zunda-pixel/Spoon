/// How diffs are computed for display.
public struct DiffOptions: Sendable, Hashable {
  /// Hide changes that only add, remove, or alter whitespace (`-w`). The
  /// resulting hunks no longer match the file byte for byte, so they cannot
  /// be staged or discarded.
  public var ignoresWhitespace: Bool

  public init(ignoresWhitespace: Bool = false) {
    self.ignoresWhitespace = ignoresWhitespace
  }

  public static let standard = DiffOptions()

  var arguments: [String] {
    ignoresWhitespace ? ["--ignore-all-space"] : []
  }
}
