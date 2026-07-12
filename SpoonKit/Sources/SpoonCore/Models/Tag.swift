public import Foundation
public import MemberwiseInit

/// A tag as reported by `git for-each-ref refs/tags`.
@MemberwiseInit(.public)
public struct Tag: Sendable, Hashable, Identifiable {
  /// Short name, e.g. `v1.2.0`.
  public var name: String
  /// The tagged commit (peeled for annotated tags).
  public var target: ObjectID
  public var isAnnotated: Bool
  public var createdAt: Date?

  public var id: String { name }
}
