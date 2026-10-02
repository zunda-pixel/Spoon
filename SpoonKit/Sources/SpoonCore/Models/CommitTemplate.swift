import Foundation
public import MemberwiseInit

/// The file `commit.template` names, split the way git's editor shows it:
/// text to start the message from, and comment lines that only guide.
@MemberwiseInit(.public)
public struct CommitTemplate: Sendable, Hashable {
  /// The template as git resolved the setting, `~` expanded.
  public var path: String
  /// Non-comment lines, with trailing blank lines removed.
  public var body: String
  /// Comment lines without their comment character.
  public var comments: [String]

  /// Splits `text` at lines starting with `commentCharacter`, as
  /// `git commit` strips them when cleaning up an edited message.
  static func parse(_ text: String, path: String, commentCharacter: Character = "#") -> CommitTemplate {
    var body: [Substring] = []
    var comments: [String] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      if line.first == commentCharacter {
        comments.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
      } else {
        body.append(line)
      }
    }
    while let last = body.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
      body.removeLast()
    }
    return CommitTemplate(
      path: path, body: body.joined(separator: "\n"), comments: comments.filter { !$0.isEmpty })
  }
}
