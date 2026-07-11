public import Foundation

/// Parses `git status --porcelain=v2 --branch -z` output.
/// Pure and stateless — fixture-tested byte-for-byte.
public enum GitStatusParser {
  public struct ParseError: Error, Sendable {
    public var record: String
  }

  public static func parse(_ data: Data) throws -> WorkingTreeStatus {
    // With -z every record (including headers) is NUL-terminated, and a
    // rename record is followed by one extra NUL-separated token holding
    // the original path.
    let tokens = String(decoding: data, as: UTF8.self)
      .split(separator: "\0", omittingEmptySubsequences: true)

    var status = WorkingTreeStatus()
    var entries: [FileStatusEntry] = []
    var index = tokens.startIndex

    while index < tokens.endIndex {
      let record = tokens[index]
      index = tokens.index(after: index)

      switch record.first {
      case "#":
        parseHeader(record, into: &status)
      case "1":
        entries.append(try parseOrdinary(record))
      case "2":
        guard index < tokens.endIndex else {
          throw ParseError(record: String(record))
        }
        let originalPath = String(tokens[index])
        index = tokens.index(after: index)
        entries.append(try parseRename(record, originalPath: originalPath))
      case "u":
        entries.append(try parseUnmerged(record))
      case "?":
        entries.append(FileStatusEntry(path: String(record.dropFirst(2)), isUntracked: true))
      case "!":
        entries.append(FileStatusEntry(path: String(record.dropFirst(2)), isIgnored: true))
      default:
        throw ParseError(record: String(record))
      }
    }

    status.entries = entries
    return status
  }

  // MARK: - Headers

  private static func parseHeader(_ record: Substring, into status: inout WorkingTreeStatus) {
    let content = record.dropFirst(2)
    if let oid = content.removingPrefix("branch.oid ") {
      status.headOID = ObjectID(rawValue: String(oid))  // "(initial)" fails validation → nil
    } else if let head = content.removingPrefix("branch.head ") {
      status.headBranch = head == "(detached)" ? nil : String(head)
    } else if let upstream = content.removingPrefix("branch.upstream ") {
      status.upstream = String(upstream)
    } else if let ab = content.removingPrefix("branch.ab ") {
      for part in ab.split(separator: " ") {
        if let ahead = part.removingPrefix("+") {
          status.ahead = Int(ahead)
        } else if let behind = part.removingPrefix("-") {
          status.behind = Int(behind)
        }
      }
    }
  }

  // MARK: - Entries

  /// `1 XY sub mH mI mW hH hI <path>` — 8 fixed fields, then the path
  /// (which may contain spaces).
  private static func parseOrdinary(_ record: Substring) throws -> FileStatusEntry {
    let fields = record.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
    guard fields.count == 9, let xy = xy(fields[1]) else {
      throw ParseError(record: String(record))
    }
    return FileStatusEntry(path: String(fields[8]), staged: xy.staged, unstaged: xy.unstaged)
  }

  /// `2 XY sub mH mI mW hH hI X<score> <path>` — 9 fixed fields, then the path;
  /// the original path arrives as the following NUL token.
  private static func parseRename(_ record: Substring, originalPath: String) throws -> FileStatusEntry {
    let fields = record.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
    guard fields.count == 10, let xy = xy(fields[1]) else {
      throw ParseError(record: String(record))
    }
    return FileStatusEntry(
      path: String(fields[9]),
      originalPath: originalPath,
      staged: xy.staged,
      unstaged: xy.unstaged
    )
  }

  /// `u XY sub m1 m2 m3 mW h1 h2 h3 <path>` — 10 fixed fields, then the path.
  private static func parseUnmerged(_ record: Substring) throws -> FileStatusEntry {
    let fields = record.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
    guard fields.count == 11, let conflict = conflict(fields[1]) else {
      throw ParseError(record: String(record))
    }
    return FileStatusEntry(path: String(fields[10]), conflict: conflict)
  }

  private static func xy(_ field: Substring) -> (staged: FileStatusEntry.Change?, unstaged: FileStatusEntry.Change?)? {
    guard field.count == 2, let x = field.first, let y = field.last else { return nil }
    return (
      staged: x == "." ? nil : FileStatusEntry.Change(rawValue: x),
      unstaged: y == "." ? nil : FileStatusEntry.Change(rawValue: y)
    )
  }

  private static func conflict(_ field: Substring) -> FileStatusEntry.Conflict? {
    switch field {
    case "DD": .bothDeleted
    case "AU": .addedByUs
    case "UD": .deletedByThem
    case "UA": .addedByThem
    case "DU": .deletedByUs
    case "AA": .bothAdded
    case "UU": .bothModified
    default: nil
    }
  }
}

extension Substring {
  fileprivate func removingPrefix(_ prefix: String) -> Substring? {
    guard hasPrefix(prefix) else { return nil }
    return dropFirst(prefix.count)
  }
}
