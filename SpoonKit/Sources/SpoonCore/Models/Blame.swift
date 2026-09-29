public import Foundation

/// The commit that last changed one or more blamed lines.
public struct BlameCommit: Sendable, Hashable {
  public var oid: ObjectID
  public var authorName: String
  public var authoredAt: Date
  public var summary: String

  public init(oid: ObjectID, authorName: String, authoredAt: Date, summary: String) {
    self.oid = oid
    self.authorName = authorName
    self.authoredAt = authoredAt
    self.summary = summary
  }

  /// Git reports working-tree edits under the all-zero object ID.
  public var isUncommitted: Bool { oid.rawValue.allSatisfy { $0 == "0" } }
}

/// One line of `git blame` output.
public struct BlameLine: Sendable, Hashable, Identifiable {
  /// 1-based line number in the blamed file.
  public var lineNumber: Int
  public var commit: BlameCommit
  public var text: String

  public init(lineNumber: Int, commit: BlameCommit, text: String) {
    self.lineNumber = lineNumber
    self.commit = commit
    self.text = text
  }

  public var id: Int { lineNumber }
}

/// Which commits blame looks past, attributing their lines to the commit
/// before them — typically reformatting or other mechanical changes.
public struct BlameOptions: Sendable, Hashable {
  /// The file GitHub and many projects use for such commits.
  public static let conventionalIgnoreRevsFile = ".git-blame-ignore-revs"

  /// Honor the listed commits: those in `blame.ignoreRevsFile`, or in
  /// `ignoreRevsFile` when that is set. `false` resets git's list.
  public var skipsListedCommits: Bool
  /// A list to read when `blame.ignoreRevsFile` isn't configured.
  public var ignoreRevsFile: String?
  /// More commits to look past, such as ones picked in the Blame view.
  public var ignoredRevisions: [ObjectID]

  public init(
    skipsListedCommits: Bool = true, ignoreRevsFile: String? = nil,
    ignoredRevisions: [ObjectID] = []
  ) {
    self.skipsListedCommits = skipsListedCommits
    self.ignoreRevsFile = ignoreRevsFile
    self.ignoredRevisions = ignoredRevisions
  }

  var arguments: [String] {
    var arguments: [String] = []
    if !skipsListedCommits {
      // An empty name clears the files git would otherwise read.
      arguments.append("--ignore-revs-file=")
    } else if let ignoreRevsFile {
      arguments += ["--ignore-revs-file", ignoreRevsFile]
    }
    for revision in ignoredRevisions {
      arguments += ["--ignore-rev", revision.rawValue]
    }
    return arguments
  }
}

/// How a repository lists commits for blame to look past.
public struct BlameIgnoreSettings: Sendable, Hashable {
  /// `blame.ignoreRevsFile` values, which git reads on every blame.
  public var configuredFiles: [String]
  /// Whether `.git-blame-ignore-revs` exists at the repository root.
  public var hasConventionalFile: Bool

  public init(configuredFiles: [String] = [], hasConventionalFile: Bool = false) {
    self.configuredFiles = configuredFiles
    self.hasConventionalFile = hasConventionalFile
  }

  /// Whether there is a list to honor at all.
  public var hasList: Bool { !configuredFiles.isEmpty || hasConventionalFile }

  /// Blame options that honor (or not) the list, plus `extra` commits.
  /// `.git-blame-ignore-revs` is passed explicitly, since git reads it only
  /// when `blame.ignoreRevsFile` names it.
  public func options(skippingListedCommits: Bool, ignoring extra: [ObjectID]) -> BlameOptions {
    BlameOptions(
      skipsListedCommits: skippingListedCommits,
      ignoreRevsFile: configuredFiles.isEmpty && hasConventionalFile
        ? BlameOptions.conventionalIgnoreRevsFile : nil,
      ignoredRevisions: extra
    )
  }

  /// The file new entries go to.
  public var listFileForAdding: String {
    configuredFiles.first ?? BlameOptions.conventionalIgnoreRevsFile
  }
}
