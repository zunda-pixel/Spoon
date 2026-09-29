import Foundation

/// Parses the git and common directory reported by `git repo info` or
/// `git rev-parse`.
enum GitRepositoryPathsParser {
  static let gitDirectoryKey = "path.gitdir.absolute"
  static let commonDirectoryKey = "path.commondir.absolute"

  /// `git repo info -z <keys>`: one `<key>\n<value>\0` record per key.
  static func parseRepoInfo(_ data: Data) -> GitRepositoryPaths? {
    var values: [String: String] = [:]
    for record in data.split(separator: 0) {
      let text = String(decoding: record, as: UTF8.self)
      guard let separator = text.firstIndex(of: "\n") else { continue }
      values[String(text[..<separator])] = String(text[text.index(after: separator)...])
    }
    return make(
      gitDirectory: values[gitDirectoryKey],
      commonDirectory: values[commonDirectoryKey]
    )
  }

  /// `git rev-parse --path-format=absolute --git-dir --git-common-dir`:
  /// one absolute path per line, in argument order.
  static func parseRevParse(_ output: String) -> GitRepositoryPaths? {
    let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count >= 2 else { return nil }
    return make(gitDirectory: String(lines[0]), commonDirectory: String(lines[1]))
  }

  private static func make(gitDirectory: String?, commonDirectory: String?) -> GitRepositoryPaths? {
    guard
      let gitDirectory, gitDirectory.hasPrefix("/"),
      let commonDirectory, commonDirectory.hasPrefix("/")
    else { return nil }
    return GitRepositoryPaths(
      gitDirectory: URL(filePath: gitDirectory, directoryHint: .isDirectory),
      commonDirectory: URL(filePath: commonDirectory, directoryHint: .isDirectory)
    )
  }
}
