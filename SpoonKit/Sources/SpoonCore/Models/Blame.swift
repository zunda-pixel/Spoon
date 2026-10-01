public import Foundation
public import MemberwiseInit

/// The commit that last changed one or more blamed lines.
@MemberwiseInit(.public)
public struct BlameCommit: Sendable, Hashable {
  public var oid: ObjectID
  public var authorName: String
  public var authoredAt: Date
  public var summary: String

  /// Git reports working-tree edits under the all-zero object ID.
  public var isUncommitted: Bool { oid.rawValue.allSatisfy { $0 == "0" } }
}

/// One line of `git blame` output.
@MemberwiseInit(.public)
public struct BlameLine: Sendable, Hashable, Identifiable {
  /// 1-based line number in the blamed file.
  public var lineNumber: Int
  public var commit: BlameCommit
  public var text: String

  public var id: Int { lineNumber }
}

/// Which commits blame looks past, attributing their lines to the commit
/// before them — typically reformatting or other mechanical changes.
@MemberwiseInit(.public)
public struct BlameOptions: Sendable, Hashable {
  /// The file GitHub and many projects use for such commits.
  public static let conventionalIgnoreRevsFile = ".git-blame-ignore-revs"

  /// Honor the listed commits: those in `blame.ignoreRevsFile`, or in
  /// `ignoreRevsFile` when that is set. `false` resets git's list.
  public var skipsListedCommits: Bool = true
  /// A list to read when `blame.ignoreRevsFile` isn't configured.
  public var ignoreRevsFile: String? = nil
  /// More commits to look past, such as ones picked in the Blame view.
  public var ignoredRevisions: [ObjectID] = []

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
@MemberwiseInit(.public)
public struct BlameIgnoreSettings: Sendable, Hashable {
  /// `blame.ignoreRevsFile` values, which git reads on every blame.
  public var configuredFiles: [String] = []
  /// Whether `.git-blame-ignore-revs` exists at the repository root.
  public var hasConventionalFile: Bool = false

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
