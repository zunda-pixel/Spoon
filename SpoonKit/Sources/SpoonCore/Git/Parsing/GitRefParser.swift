public import Foundation

/// Parses `git for-each-ref refs/heads` with `branchFormat` into `[Branch]`.
/// Pure and stateless — fixture-tested byte-for-byte.
public enum GitRefParser {
  /// NUL-separated fields, newline-separated records (ref names and commit
  /// subjects can contain neither).
  public static let branchFormat =
    "%(HEAD)%00%(refname:short)%00%(objectname)%00%(subject)%00%(upstream:short)%00%(upstream:track)%00%(committerdate:unix)"

  public struct ParseError: Error, Sendable {
    public var line: String
  }

  public static func parseBranches(_ data: Data) throws -> [Branch] {
    let text = String(decoding: data, as: UTF8.self)
    return try text.split(separator: "\n", omittingEmptySubsequences: true).map { line in
      let fields = line.split(separator: "\0", omittingEmptySubsequences: false)
      guard fields.count == 7, let tip = ObjectID(rawValue: String(fields[2])) else {
        throw ParseError(line: String(line))
      }
      let track = parseTrack(fields[5])
      return Branch(
        name: String(fields[1]),
        isCurrent: fields[0] == "*",
        tip: tip,
        subject: String(fields[3]),
        upstream: fields[4].isEmpty ? nil : String(fields[4]),
        ahead: track.ahead,
        behind: track.behind,
        upstreamGone: track.gone,
        committedAt: TimeInterval(fields[6]).map(Date.init(timeIntervalSince1970:))
      )
    }
  }

  /// `%(upstream:track)` renders as `[ahead 1, behind 2]`, `[ahead 1]`,
  /// `[behind 2]`, `[gone]`, or empty (in sync / no upstream).
  private static func parseTrack(_ field: Substring) -> (ahead: Int?, behind: Int?, gone: Bool) {
    guard field.hasPrefix("["), field.hasSuffix("]") else { return (nil, nil, false) }
    let inner = field.dropFirst().dropLast()
    if inner == "gone" { return (nil, nil, true) }

    var ahead: Int?
    var behind: Int?
    for part in inner.split(separator: ",") {
      let trimmed = part.trimmingCharacters(in: .whitespaces)
      if let value = trimmed.split(separator: " ").last.flatMap({ Int($0) }) {
        if trimmed.hasPrefix("ahead") { ahead = value }
        if trimmed.hasPrefix("behind") { behind = value }
      }
    }
    return (ahead, behind, false)
  }
}
