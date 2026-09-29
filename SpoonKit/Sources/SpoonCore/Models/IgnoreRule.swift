import Foundation

/// The `.gitignore`-style line that decides whether a path is ignored.
public struct IgnoreRule: Sendable, Hashable {
  /// The file the pattern is in: a repository-relative `.gitignore`,
  /// `.git/info/exclude`, or an absolute `core.excludesFile`.
  public var source: String
  /// 1-based line of the pattern in `source`.
  public var line: Int
  public var pattern: String

  public init(source: String, line: Int, pattern: String) {
    self.source = source
    self.line = line
    self.pattern = pattern
  }

  /// A `!pattern` re-includes the path, so it is not ignored after all.
  public var reincludes: Bool { pattern.hasPrefix("!") }

  /// Parses `git check-ignore --stdin -z --verbose --non-matching`: four
  /// NUL-terminated fields per path (source, line, pattern, path), the
  /// first three empty when no pattern matches.
  static func parse(_ output: String) -> [String: IgnoreRule?] {
    let fields = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
    var rules: [String: IgnoreRule?] = [:]
    var index = 0
    while index + 3 < fields.count {
      let path = fields[index + 3]
      if let line = Int(fields[index + 1]), !fields[index].isEmpty {
        rules[path] = IgnoreRule(source: fields[index], line: line, pattern: fields[index + 2])
      } else {
        rules[path] = .some(nil)
      }
      index += 4
    }
    return rules
  }
}

/// Why a path is, or isn't, ignored.
public enum IgnoreStatus: Sendable, Hashable {
  /// Tracked files are never ignored, whatever the patterns say.
  case tracked
  case ignored(IgnoreRule)
  /// A `!pattern` matched last, so the path is not ignored.
  case reincluded(IgnoreRule)
  case notIgnored
}
