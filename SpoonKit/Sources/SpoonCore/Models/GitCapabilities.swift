/// A `major.minor.patch` git release, ignoring vendor and release-candidate suffixes.
public struct GitVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
  public var major: Int
  public var minor: Int
  public var patch: Int

  public init(_ major: Int, _ minor: Int, _ patch: Int = 0) {
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  public var description: String { "\(major).\(minor).\(patch)" }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
  }
}

/// Optional git features Spoon can use, derived from the installed git version.
///
/// Every feature defaults to unavailable, so an unknown or unparsable version
/// hides version-gated UI instead of offering commands git would reject.
public struct GitCapabilities: Sendable, Hashable {
  /// `nil` when `git version` failed or printed something unrecognizable.
  public var version: GitVersion?

  public init(version: GitVersion? = nil) {
    self.version = version
  }

  /// `git backfill` (2.49+).
  public var supportsBackfill: Bool { supports(GitVersion(2, 49)) }

  /// `git add --resolved`, which refuses paths with leftover conflict
  /// markers (2.56+).
  public var supportsAddResolved: Bool { supports(GitVersion(2, 56)) }

  /// `git branch --delete-merged` (2.56+).
  public var supportsDeleteMergedBranches: Bool { supports(GitVersion(2, 56)) }

  /// `git branch --forked` (2.56+).
  public var supportsForkedBranchFilter: Bool { supports(GitVersion(2, 56)) }

  /// `git cat-file --batch-command` `remote-object-info` and
  /// `git rev-list --missing-only` (2.56+).
  public var supportsRemoteObjectInfo: Bool { supports(GitVersion(2, 56)) }

  /// `git repack --drop-filtered` for partial clones (2.56+).
  public var supportsRepackDropFiltered: Bool { supports(GitVersion(2, 56)) }

  /// `git replay --linearize` with atomic `--ref-action=update` (2.56+).
  public var supportsReplayLinearize: Bool { supports(GitVersion(2, 56)) }

  /// `git refs create/update/delete/rename` (2.56+).
  public var supportsRefsWriteCommands: Bool { supports(GitVersion(2, 56)) }

  /// `git history drop` (2.56+).
  public var supportsHistoryDrop: Bool { supports(GitVersion(2, 56)) }

  /// `git repo info` path keys such as `path.gitdir.absolute` (2.56+).
  public var supportsRepoInfoPaths: Bool { supports(GitVersion(2, 56)) }

  private func supports(_ minimum: GitVersion) -> Bool {
    guard let version else { return false }
    return version >= minimum
  }
}
