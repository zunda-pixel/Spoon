public import MemberwiseInit

/// A configured remote (`git remote -v`).
@MemberwiseInit(.public)
public struct Remote: Sendable, Hashable, Identifiable {
  public var name: String
  public var fetchURL: String
  public var pushURL: String? = nil

  public var id: String { name }
}
