public import MemberwiseInit

/// A `major.minor.patch` git release, ignoring vendor and release-candidate suffixes.
@MemberwiseInit(.public)
public struct GitVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
  @Init(label: "_")
  public var major: Int
  @Init(label: "_")
  public var minor: Int
  @Init(label: "_")
  public var patch: Int = 0

  public var description: String { "\(major).\(minor).\(patch)" }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
  }
}

/// Optional git features Spoon can use, derived from the installed git version.
///
/// Every feature defaults to unavailable, so an unknown or unparsable version
/// hides version-gated UI instead of offering commands git would reject.
@MemberwiseInit(.public)
public struct GitCapabilities: Sendable, Hashable {
  /// `nil` when `git version` failed or printed something unrecognizable.
  public var version: GitVersion? = nil

  /// `git backfill` (2.49+).
  public var supportsBackfill: Bool { supports(GitVersion(2, 49)) }

  /// `git add --resolved`, which refuses paths with leftover conflict
  /// markers (2.56+).
  public var supportsAddResolved: Bool { supports(GitVersion(2, 56)) }

  /// `git bisect start --reset-when-found` (2.56+).
  public var supportsBisectResetWhenFound: Bool { supports(GitVersion(2, 56)) }

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

  /// `git history reword` (2.54+).
  public var supportsHistoryReword: Bool { supports(GitVersion(2, 54)) }

  /// `git history fixup` (2.55+).
  public var supportsHistoryFixup: Bool { supports(GitVersion(2, 55)) }

  /// `git history drop` (2.56+).
  public var supportsHistoryDrop: Bool { supports(GitVersion(2, 56)) }

  /// `git repo info` path keys such as `path.gitdir.absolute` (2.56+).
  public var supportsRepoInfoPaths: Bool { supports(GitVersion(2, 56)) }

  private func supports(_ minimum: GitVersion) -> Bool {
    guard let version else { return false }
    return version >= minimum
  }
}
