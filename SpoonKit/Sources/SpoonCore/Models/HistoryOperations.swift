public import Foundation

public enum ResetMode: String, Sendable, Hashable, CaseIterable {
  case soft
  case mixed
  case hard
}

public struct ReflogEntry: Sendable, Hashable, Identifiable {
  public var oid: ObjectID
  public var selector: String
  public var subject: String
  public var authorName: String
  public var authorEmail: String
  public var date: Date

  public var id: String { selector }

  public init(
    oid: ObjectID,
    selector: String,
    subject: String,
    authorName: String,
    authorEmail: String,
    date: Date
  ) {
    self.oid = oid
    self.selector = selector
    self.subject = subject
    self.authorName = authorName
    self.authorEmail = authorEmail
    self.date = date
  }
}
