public import MemberwiseInit

/// One file's patch within a diff.
@MemberwiseInit(.public)
public struct FileDiff: Sendable, Hashable, Identifiable {
  public enum ChangeKind: Sendable, Hashable {
    case modified
    case added
    case deleted
    case renamed
    case copied
  }

  /// New path (or old path for deletions).
  public var path: String
  /// Pre-rename/copy path.
  public var oldPath: String? = nil
  public var kind: ChangeKind = .modified
  public var isBinary: Bool = false
  public var oldMode: String? = nil
  public var newMode: String? = nil
  public var hunks: [Hunk] = []

  public var id: String { path }

  public var additionCount: Int {
    hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .addition } }
  }

  public var deletionCount: Int {
    hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .deletion } }
  }

  public var lineCount: Int {
    hunks.reduce(0) { $0 + $1.lines.count }
  }
}

/// One `@@ -a,b +c,d @@` block.
@MemberwiseInit(.public)
public struct Hunk: Sendable, Hashable, Identifiable {
  /// The verbatim `@@ …` header line (kept byte-exact for patch rebuilding).
  public var header: String
  public var oldStart: Int
  public var oldCount: Int
  public var newStart: Int
  public var newCount: Int
  public var lines: [DiffLine]

  public var id: String { "\(oldStart)+\(newStart)" }
}

public struct DiffLine: Sendable, Hashable {
  public enum Kind: Sendable, Hashable {
    case context
    case addition
    case deletion
    /// `\ No newline at end of file` — must survive round trips.
    case noNewlineMarker
  }

  public var kind: Kind
  /// Content without the leading `+`/`-`/space marker.
  public var text: String
  /// 1-based line number in the old file (context and deletions).
  public var oldLine: Int?
  /// 1-based line number in the new file (context and additions).
  public var newLine: Int?

  public init(kind: Kind, text: String, oldLine: Int? = nil, newLine: Int? = nil) {
    self.kind = kind
    self.text = text
    self.oldLine = oldLine
    self.newLine = newLine
  }
}

/// Full detail for one commit: metadata, message, and first-parent patch.
@MemberwiseInit(.public)
public struct CommitDetail: Sendable, Hashable {
  public var commit: Commit
  public var fullMessage: String
  public var diffs: [FileDiff]
}
