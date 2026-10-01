public import Foundation
public import MemberwiseInit

public enum ResetMode: String, Sendable, Hashable, CaseIterable {
  case soft
  case mixed
  case hard
}

@MemberwiseInit(.public)
public struct ReflogEntry: Sendable, Hashable, Identifiable {
  public var oid: ObjectID
  public var selector: String
  public var subject: String
  public var authorName: String
  public var authorEmail: String
  public var date: Date

  public var id: String { selector }
}
