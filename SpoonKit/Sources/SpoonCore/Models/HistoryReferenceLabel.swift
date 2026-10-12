public import Foundation
public import MemberwiseInit

/// Stable identity for a branch reference that can focus the unified history.
public enum HistoryReferenceIdentity: Sendable, Hashable {
  case localBranch(String)
  case remoteBranch(remote: String, name: String)
  case tag(String)

  public var name: String {
    switch self {
    case .localBranch(let name), .remoteBranch(_, let name), .tag(let name):
      name
    }
  }
}

/// One reference badge displayed beside a commit in the unified history.
@MemberwiseInit(.public)
public struct HistoryReferenceLabel: Sendable, Hashable, Identifiable {
  public enum Kind: Int, Sendable, Hashable {
    case localBranch
    case remoteBranch
    case worktree
    case tag
    case stash
  }

  public let id: String
  public let name: String
  public let kind: Kind
  @Init(default: false)
  public let isCurrent: Bool
  @Init(default: false)
  public let isCheckedOutInWorktree: Bool
  @Init(default: nil)
  public let referenceIdentity: HistoryReferenceIdentity?
  /// The upstream (such as `origin/main`) of a local branch whose tip it
  /// shares. Its own label is folded into this one.
  @Init(default: nil)
  public var syncedUpstream: String?
}

/// Builds deterministic commit-to-reference mappings independently of SwiftUI.
public enum HistoryReferenceLabelBuilder {
  public static func build(
    branches: [Branch],
    remoteBranchesByRemote: [String: [Branch]],
    worktrees: [Worktree],
    tags: [Tag],
    stashes: [Stash],
    activeWorktreeRoot: URL? = nil,
    selectedReference: HistoryReferenceIdentity? = nil,
    visibleReferenceIDs: Set<String>? = nil
  ) -> [ObjectID: [HistoryReferenceLabel]] {
    var labelsByOID: [ObjectID: [HistoryReferenceLabel]] = [:]
    let worktreeBranchNames = Set(worktrees.compactMap(\.branch))

    for branch in branches {
      let filterID = HistoryReferenceFilterID.localBranch(branch.name).id
      guard visibleReferenceIDs == nil || visibleReferenceIDs?.contains(filterID) == true else {
        continue
      }
      let identity = HistoryReferenceIdentity.localBranch(branch.name)
      labelsByOID[branch.tip, default: []].append(
        HistoryReferenceLabel(
          id: "local:\(branch.name)",
          name: branch.name,
          kind: .localBranch,
          isCurrent: branch.isCurrent,
          isCheckedOutInWorktree: worktreeBranchNames.contains(branch.name),
          referenceIdentity: identity
        )
      )
    }

    for remoteName in remoteBranchesByRemote.keys.sorted() {
      for branch in remoteBranchesByRemote[remoteName] ?? [] {
        let filterID = HistoryReferenceFilterID.remoteBranch(
          remote: remoteName,
          name: branch.name
        ).id
        guard visibleReferenceIDs == nil || visibleReferenceIDs?.contains(filterID) == true else {
          continue
        }
        let identity = HistoryReferenceIdentity.remoteBranch(
          remote: remoteName,
          name: branch.name
        )
        labelsByOID[branch.tip, default: []].append(
          HistoryReferenceLabel(
            id: "remote:\(remoteName):\(branch.name)",
            name: branch.name,
            kind: .remoteBranch,
            referenceIdentity: identity
          )
        )
      }
    }

    for tag in tags {
      let filterID = HistoryReferenceFilterID.tag(tag.name).id
      guard visibleReferenceIDs == nil || visibleReferenceIDs?.contains(filterID) == true else {
        continue
      }
      labelsByOID[tag.target, default: []].append(
        HistoryReferenceLabel(
          id: "tag:\(tag.name)",
          name: tag.name,
          kind: .tag,
          referenceIdentity: .tag(tag.name)
        )
      )
    }

    for stash in stashes {
      labelsByOID[stash.target, default: []].append(
        HistoryReferenceLabel(
          id: "stash:\(stash.index)",
          name: stash.reference,
          kind: .stash
        )
      )
    }

    // A local branch and its upstream at the same commit show as one label,
    // unless the upstream is the focused reference.
    let upstreamByLocalLabelID = Dictionary(
      uniqueKeysWithValues: branches.compactMap { branch in
        branch.upstream.map { ("local:\(branch.name)", $0) }
      }
    )
    labelsByOID = labelsByOID.mapValues { labels in
      let remoteNames = Set(
        labels.filter {
          $0.kind == .remoteBranch && $0.referenceIdentity != selectedReference
        }.map(\.name)
      )
      var folded: Set<String> = []
      var merged = labels.map { label in
        var label = label
        if label.kind == .localBranch, let upstream = upstreamByLocalLabelID[label.id],
          remoteNames.contains(upstream)
        {
          label.syncedUpstream = upstream
          folded.insert(upstream)
        }
        return label
      }
      merged.removeAll { $0.kind == .remoteBranch && folded.contains($0.name) }
      return merged
    }

    return labelsByOID.mapValues { labels in
      labels.sorted { lhs, rhs in
        let lhsSelected = lhs.referenceIdentity == selectedReference
        let rhsSelected = rhs.referenceIdentity == selectedReference
        if lhsSelected != rhsSelected { return lhsSelected }
        if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
        if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id < rhs.id
      }
    }
  }
}
