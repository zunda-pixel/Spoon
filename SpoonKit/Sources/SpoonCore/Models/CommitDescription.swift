import Foundation

/// Where a commit sits relative to the repository's tags.
public struct CommitDescription: Sendable, Hashable {
  /// The closest tag at or before the commit (`git describe --tags`).
  public var nearestTag: String?
  /// Commits between `nearestTag` and this one; 0 when it is tagged itself.
  public var commitsSinceTag: Int
  /// The first tag that includes the commit (`git describe --contains`),
  /// i.e. the release it shipped in; `nil` while no tag contains it.
  public var firstContainingTag: String?

  public init(nearestTag: String?, commitsSinceTag: Int = 0, firstContainingTag: String? = nil) {
    self.nearestTag = nearestTag
    self.commitsSinceTag = commitsSinceTag
    self.firstContainingTag = firstContainingTag
  }

  public var isEmpty: Bool { nearestTag == nil && firstContainingTag == nil }

  /// Parses `git describe --tags --long` output, `v1.2-3-gabc1234`. Tag
  /// names may contain dashes, so the count and hash are taken from the
  /// end; `--long` guarantees they are there, even for a tagged commit.
  static func parseNearest(_ output: String) -> (tag: String, distance: Int)? {
    let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    if parts.count >= 3, let distance = Int(parts[parts.count - 2]),
      parts[parts.count - 1].hasPrefix("g"),
      parts[parts.count - 1].dropFirst().allSatisfy(\.isHexDigit)
    {
      return (parts.dropLast(2).joined(separator: "-"), distance)
    }
    return (text, 0)
  }

  /// Parses `git describe --contains` output such as `v1.3~2` or
  /// `v1.3^2~1` down to the tag name.
  static func parseContaining(_ output: String) -> String? {
    let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
    let tag = text.prefix { $0 != "~" && $0 != "^" }
    return tag.isEmpty ? nil : String(tag)
  }
}
