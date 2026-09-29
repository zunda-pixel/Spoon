/// One reference move reported by a history-rewriting git command.
public struct RefUpdate: Sendable, Hashable, Identifiable {
  /// Full reference name, such as `refs/heads/main` or `HEAD`.
  public var reference: String
  public var newOID: ObjectID
  public var oldOID: ObjectID

  public init(reference: String, newOID: ObjectID, oldOID: ObjectID) {
    self.reference = reference
    self.newOID = newOID
    self.oldOID = oldOID
  }

  public var id: String { reference }

  /// The local branch name when `reference` is under `refs/heads/`.
  public var branchName: String? {
    let prefix = "refs/heads/"
    guard reference.hasPrefix(prefix) else { return nil }
    return String(reference.dropFirst(prefix.count))
  }
}
