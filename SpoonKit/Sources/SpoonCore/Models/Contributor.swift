import Foundation
public import MemberwiseInit

/// One author and how many commits they made, after `.mailmap` folds
/// their names and addresses together (`git shortlog -sne`).
@MemberwiseInit(.public)
public struct Contributor: Sendable, Hashable, Identifiable {
  public var name: String
  public var email: String
  public var commitCount: Int

  public var id: String { "\(name) <\(email)>" }

  /// Parses `git shortlog -sne`: `<count>\t<name> <<email>>` per line,
  /// already sorted by count.
  static func parse(_ output: String) -> [Contributor] {
    output.split(whereSeparator: \.isNewline).compactMap { line in
      guard let tab = line.firstIndex(of: "\t"),
        let count = Int(line[..<tab].trimmingCharacters(in: .whitespaces))
      else { return nil }
      let identity = line[line.index(after: tab)...]
      guard identity.hasSuffix(">"), let open = identity.lastIndex(of: "<") else {
        return Contributor(name: String(identity), email: "", commitCount: count)
      }
      return Contributor(
        name: identity[..<open].trimmingCharacters(in: .whitespaces),
        email: String(identity[identity.index(after: open)..<identity.index(before: identity.endIndex)]),
        commitCount: count
      )
    }
  }
}
