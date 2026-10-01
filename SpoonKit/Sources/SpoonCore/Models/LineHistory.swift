import Foundation
public import MemberwiseInit

/// One commit that changed a range of lines, with just that part of its diff.
@MemberwiseInit(.public)
public struct LineHistoryEntry: Sendable, Hashable, Identifiable {
  public var commit: Commit
  public var diffs: [FileDiff]

  public var id: ObjectID { commit.oid }
}

enum LineHistoryParser {
  /// Record separator before each commit's header line.
  static let format = "%x1e" + GitLogParser.logFormat

  /// Parses `git log -L … --format=<format>`: each record is a header in
  /// `GitLogParser.logFormat`, a newline, then that commit's patch.
  static func parse(_ data: Data) throws -> [LineHistoryEntry] {
    try data.split(separator: 0x1E).compactMap { record in
      guard let newline = record.firstIndex(of: UInt8(ascii: "\n")) else {
        return try entry(header: record, patch: Data())
      }
      return try entry(
        header: record[record.startIndex..<newline],
        patch: Data(record[record.index(after: newline)...])
      )
    }
  }

  private static func entry(header: Data.SubSequence, patch: Data) throws -> LineHistoryEntry? {
    guard let commit = try GitLogParser.parse(Data(header) + Data([0])).first else { return nil }
    return LineHistoryEntry(commit: commit, diffs: try GitDiffParser.parse(patch))
  }
}
