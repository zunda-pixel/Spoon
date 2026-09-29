import Foundation

/// One submodule of the repository, as `git submodule status` reports it.
public struct Submodule: Sendable, Hashable, Identifiable {
  public enum State: Sendable, Hashable {
    /// Checked out at the commit the superproject records.
    case upToDate
    /// Listed in `.gitmodules` but never initialized or checked out.
    case notInitialized
    /// Checked out at a different commit than the one recorded.
    case differentCommit
    /// The recorded commit conflicts in a merge.
    case conflicted
  }

  /// Path relative to the repository root.
  public var path: String
  public var state: State
  /// The checked-out commit, or the recorded one when not initialized.
  public var commit: ObjectID
  /// `git describe` of `commit`, such as `heads/main` or `v1.2`.
  public var describe: String?
  /// The name `.gitmodules` knows it by; usually its path.
  public var name: String?
  /// URL from `.gitmodules`; may be relative to the superproject's remote.
  public var url: String?

  public var id: String { path }

  public init(
    path: String,
    state: State,
    commit: ObjectID,
    describe: String? = nil,
    name: String? = nil,
    url: String? = nil
  ) {
    self.path = path
    self.state = state
    self.commit = commit
    self.describe = describe
    self.name = name
    self.url = url
  }
}

enum SubmoduleParser {
  /// Parses `git submodule status`: `[ -+U]<oid> <path>[ (<describe>)]`.
  static func parseStatus(_ output: String) -> [Submodule] {
    output.split(whereSeparator: \.isNewline).compactMap { line in
      guard let marker = line.first else { return nil }
      let state: Submodule.State
      switch marker {
      case " ": state = .upToDate
      case "-": state = .notInitialized
      case "+": state = .differentCommit
      case "U": state = .conflicted
      default: return nil
      }
      let rest = line.dropFirst()
      guard let space = rest.firstIndex(of: " "),
        let commit = ObjectID(rawValue: String(rest[..<space]))
      else { return nil }
      var path = rest[rest.index(after: space)...]
      var describe: String?
      if path.hasSuffix(")"), let open = path.range(of: " (", options: .backwards) {
        describe = String(path[open.upperBound..<path.index(before: path.endIndex)])
        path = path[..<open.lowerBound]
      }
      return Submodule(path: String(path), state: state, commit: commit, describe: describe)
    }
  }

  /// Parses `git config --null -f .gitmodules --get-regexp` output
  /// (`key LF value NUL` records; names may contain spaces) into
  /// `(name, url)` by path.
  static func parseModules(_ output: String) -> [String: (name: String, url: String?)] {
    var paths: [String: String] = [:]
    var urls: [String: String] = [:]
    for record in output.split(separator: "\0") {
      guard let newline = record.firstIndex(of: "\n") else { continue }
      let key = record[..<newline]
      let value = String(record[record.index(after: newline)...])
      guard key.hasPrefix("submodule.") else { continue }
      let body = key.dropFirst("submodule.".count)
      if body.hasSuffix(".path") {
        paths[String(body.dropLast(".path".count))] = value
      } else if body.hasSuffix(".url") {
        urls[String(body.dropLast(".url".count))] = value
      }
    }
    var modules: [String: (name: String, url: String?)] = [:]
    for (name, path) in paths {
      modules[path] = (name, urls[name])
    }
    return modules
  }
}
