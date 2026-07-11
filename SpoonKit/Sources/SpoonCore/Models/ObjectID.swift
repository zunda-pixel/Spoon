/// A git object id (SHA-1 or SHA-256 hex).
public struct ObjectID: Sendable, Hashable, Codable, RawRepresentable, CustomStringConvertible {
  public let rawValue: String

  public init?(rawValue: String) {
    guard rawValue.count >= 4, rawValue.count <= 64,
      rawValue.allSatisfy(\.isHexDigit)
    else { return nil }
    self.rawValue = rawValue
  }

  public var shortened: String { String(rawValue.prefix(7)) }

  public var description: String { rawValue }
}
