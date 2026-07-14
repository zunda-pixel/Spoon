/// A repository reference that can be included in or excluded from history.
public enum HistoryReferenceFilterID: Sendable, Hashable, Codable {
  case localBranch(String)
  case remoteBranch(remote: String, name: String)
  case tag(String)

  public var id: String {
    switch self {
    case .localBranch(let name):
      "local:" + name
    case .remoteBranch(let remote, let name):
      "remote:" + remote + ":" + name
    case .tag(let name):
      "tag:" + name
    }
  }

  public var gitReference: String {
    switch self {
    case .localBranch(let name):
      return "refs/heads/" + name
    case .remoteBranch(let remote, let name):
      let prefix = remote + "/"
      let shortName = name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
      return "refs/remotes/" + remote + "/" + shortName
    case .tag(let name):
      return "refs/tags/" + name
    }
  }

  public init?(id: String) {
    if id.hasPrefix("local:") {
      self = .localBranch(String(id.dropFirst("local:".count)))
    } else if id.hasPrefix("remote:") {
      let value = String(id.dropFirst("remote:".count))
      guard let separator = value.firstIndex(of: ":") else { return nil }
      self = .remoteBranch(
        remote: String(value[..<separator]),
        name: String(value[value.index(after: separator)...])
      )
    } else if id.hasPrefix("tag:") {
      self = .tag(String(id.dropFirst("tag:".count)))
    } else {
      return nil
    }
  }
}
