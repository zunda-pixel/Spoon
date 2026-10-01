import Algorithms
import Foundation
public import MemberwiseInit

/// One `git config` value and the file it came from.
@MemberwiseInit(.public)
public struct GitConfigEntry: Sendable, Hashable {
  /// `system`, `global`, `local`, `worktree`, or `command`.
  public var scope: String
  /// Lowercased section and variable name, as git prints it.
  public var key: String
  public var value: String

  /// Parses `git config --null --show-scope --get-regexp`: records of
  /// `scope NUL key LF value NUL`.
  static func parse(_ output: String) -> [Self] {
    let fields = output.split(separator: "\0", omittingEmptySubsequences: false)
    return fields.chunks(ofCount: 2).compactMap { pair in
      // A trailing field after the last NUL has no partner.
      guard pair.count == 2, let scope = pair.first, let record = pair.last else { return nil }
      guard let newline = record.firstIndex(of: "\n") else {
        // A bare key (no `=`) is a boolean true.
        return record.isEmpty ? nil : Self(scope: String(scope), key: String(record), value: "true")
      }
      return Self(
        scope: String(scope),
        key: String(record[..<newline]),
        value: String(record[record.index(after: newline)...])
      )
    }
  }
}

/// The settings Spoon edits for one repository, as `git config` resolves
/// them: this repository's own values over the user's and the system's.
@MemberwiseInit(.public)
public struct RepositoryConfig: Sendable, Hashable {
  public var entries: [GitConfigEntry] = []

  /// This repository's value (`.git/config`); `nil` when it inherits one.
  public func localValue(_ key: RepositorySetting) -> String? {
    entries.last { $0.scope == "local" && $0.key == key.rawValue.lowercased() }?.value
  }

  /// The value it would have without a local one, and where that is from.
  public func inheritedValue(_ key: RepositorySetting) -> GitConfigEntry? {
    entries.last { $0.scope != "local" && $0.key == key.rawValue.lowercased() }
  }
}

/// A `git config` variable the Repository Settings sheet edits.
public enum RepositorySetting: String, Sendable, Hashable, CaseIterable {
  case userName = "user.name"
  case userEmail = "user.email"
  case pullRebase = "pull.rebase"
  case pullFastForward = "pull.ff"
  case fetchPrune = "fetch.prune"
  case pushAutoSetupRemote = "push.autoSetupRemote"
  case commitSign = "commit.gpgSign"
  case tagSign = "tag.gpgSign"
  case signingFormat = "gpg.format"
  case signingKey = "user.signingKey"
  case blameIgnoreRevsFile = "blame.ignoreRevsFile"
  case rerereEnabled = "rerere.enabled"
  case rerereAutoUpdate = "rerere.autoUpdate"

  /// A regular expression matching every setting, for `--get-regexp`.
  static var pattern: String {
    "^(" + allCases.map { NSRegularExpression.escapedPattern(for: $0.rawValue.lowercased()) }
      .joined(separator: "|") + ")$"
  }
}
