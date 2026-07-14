public import Foundation

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
  public let isCurrent: Bool
  public let referenceIdentity: HistoryReferenceIdentity?

  public init(
    id: String,
    name: String,
    kind: Kind,
    isCurrent: Bool = false,
    referenceIdentity: HistoryReferenceIdentity? = nil
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.isCurrent = isCurrent
    self.referenceIdentity = referenceIdentity
  }
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
    let activeWorktreeID = activeWorktreeRoot.map { Repository(rootURL: $0).id }

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

    for worktree in worktrees {
      guard let oid = worktree.headOID else { continue }
      labelsByOID[oid, default: []].append(
        HistoryReferenceLabel(
          id: "worktree:\(worktree.path.path)",
          name: worktree.name,
          kind: .worktree,
          isCurrent: Repository(rootURL: worktree.path).id == activeWorktreeID
        )
      )
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
