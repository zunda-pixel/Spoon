import Observation
import SpoonCore

enum SidebarItem: Hashable {
  case changes
  case history
  case reflog
  case branch(String)
  case remoteBranch(remote: String, branch: String)
  case tag(String)
  case pullRequests
  case remote(String)
  case stash(Int)
}

extension SidebarItem {
  /// A stable order for picking a primary row out of a multi-selection.
  fileprivate var sortKey: String {
    switch self {
    case .changes: "0"
    case .history: "1"
    case .reflog: "2"
    case .branch(let name): "3" + name
    case .remoteBranch(let remote, let branch): "4" + remote + "/" + branch
    case .tag(let name): "5" + name
    case .pullRequests: "6"
    case .remote(let name): "7" + name
    case .stash(let index): "8" + String(index)
    }
  }
}

struct HistoryFocus: Hashable {
  let tip: ObjectID
  let reference: HistoryReferenceIdentity

  var name: String { reference.name }
}

@MainActor
@Observable
final class RepositoryNavigationState {
  enum ActiveSheet: Hashable, Identifiable {
    case newBranch(startPoint: String?)
    case sparseCheckout
    case stashChanges(paths: [String])
    case stashBranch(Stash)
    case dropLargeBlobs
    case backfill
    case fileHistory(path: String)
    case blame(path: String)
    case lineHistory(path: String, lines: ClosedRange<Int>)
    case codeSearch
    case addRemote
    case addSubmodule
    case addWorktree(Branch)
    case addRemoteWorktree(RemoteBranchSelection)
    case renameBranch(Branch)
    case deleteBranch(Branch)
    case deleteMergedBranches
    case deleteWorktree(Worktree)
    case lockWorktree(Worktree)
    case renameRemoteBranch(RemoteBranchSelection)
    case mergeBranch(Branch)
    case compareBranchVersions(Branch)
    case replayBranch(Branch)
    case rebase(Commit)
    case autosquash
    case startBisect(Commit)
    case dropCommit(Commit)
    case fixupCommit(Commit)
    case rewordCommit(Commit)
    case moveBranch(Branch, to: Commit)
    case tag(Commit)
    case reset(target: ObjectID, description: String)
    case review(ReviewReport)
    case deleteBranches([Branch])

    var id: String {
      switch self {
      case .newBranch(let startPoint):
        "new-branch:\(startPoint ?? "HEAD")"
      case .sparseCheckout:
        "sparse-checkout"
      case .stashChanges(let paths):
        "stash-changes:\(paths.joined(separator: "\u{0}"))"
      case .dropLargeBlobs:
        "drop-large-blobs"
      case .backfill:
        "backfill"
      case .fileHistory(let path):
        "file-history:\(path)"
      case .blame(let path):
        "blame:\(path)"
      case .addRemote:
        "add-remote"
      case .addWorktree(let branch):
        "add-worktree:\(branch.id)"
      case .addRemoteWorktree(let selection):
        "add-remote-worktree:\(selection.id)"
      case .renameBranch(let branch):
        "rename-branch:\(branch.id)"
      case .deleteBranch(let branch):
        "delete-branch:\(branch.id)"
      case .deleteMergedBranches:
        "delete-merged-branches"
      case .codeSearch:
        "code-search"
      case .stashBranch(let stash):
        "stash-branch:\(stash.target.rawValue)"
      case .lineHistory(let path, let lines):
        "line-history:\(path):\(lines.lowerBound)-\(lines.upperBound)"
      case .addSubmodule:
        "add-submodule"
      case .deleteWorktree(let worktree):
        "delete-worktree:\(worktree.id)"
      case .lockWorktree(let worktree):
        "lock-worktree:\(worktree.id)"
      case .renameRemoteBranch(let selection):
        "rename-remote-branch:\(selection.id)"
      case .mergeBranch(let branch):
        "merge-branch:\(branch.id)"
      case .compareBranchVersions(let branch):
        "compare-branch-versions:\(branch.id)"
      case .replayBranch(let branch):
        "replay-branch:\(branch.id)"
      case .rebase(let commit):
        "rebase:\(commit.id)"
      case .autosquash:
        "autosquash"
      case .startBisect(let commit):
        "start-bisect:\(commit.id)"
      case .moveBranch(let branch, let commit):
        "move-branch:\(branch.id):\(commit.id)"
      case .dropCommit(let commit):
        "drop-commit:\(commit.id)"
      case .fixupCommit(let commit):
        "fixup-commit:\(commit.id)"
      case .rewordCommit(let commit):
        "reword-commit:\(commit.id)"
      case .tag(let commit):
        "tag:\(commit.id)"
      case .reset(let target, _):
        "reset:\(target.rawValue)"
      case .review(let report):
        "review:\(report.hashValue)"
      case .deleteBranches(let branches):
        "delete-branches:\(branches.map(\.id).joined(separator: "\u{0}"))"
      }
    }
  }

  enum Confirmation: String, Identifiable {
    case forcePush
    case abortSequencer

    var id: Self { self }
  }

  /// The sidebar row whose content the window shows.
  var sidebarSelection: SidebarItem? {
    get { primarySidebarSelection }
    set {
      primarySidebarSelection = newValue
      storedSidebarSelections = newValue.map { [$0] } ?? []
    }
  }

  /// Every selected sidebar row; more than one after ⌘- or ⇧-clicking.
  /// The content column keeps showing the primary selection.
  var sidebarSelections: Set<SidebarItem> {
    get { storedSidebarSelections }
    set {
      storedSidebarSelections = newValue
      if let primary = primarySidebarSelection, newValue.contains(primary) { return }
      primarySidebarSelection = newValue.min { $0.sortKey < $1.sortKey }
    }
  }

  /// Names of the local branches in the sidebar selection.
  var selectedBranchNames: Set<String> {
    var names: Set<String> = []
    for case .branch(let name) in storedSidebarSelections {
      names.insert(name)
    }
    return names
  }

  private var primarySidebarSelection: SidebarItem? = .changes
  private var storedSidebarSelections: Set<SidebarItem> = [.changes]
  /// The history commit whose details are shown.
  var selectedCommitID: String? {
    get { primaryCommitID }
    set {
      primaryCommitID = newValue
      storedCommitIDs = newValue.map { [$0] } ?? []
    }
  }

  /// Every selected history commit; more than one after ⌘- or ⇧-clicking.
  var selectedCommitIDs: Set<String> {
    get { storedCommitIDs }
    set {
      storedCommitIDs = newValue
      if let primary = primaryCommitID, newValue.contains(primary) { return }
      primaryCommitID = newValue.min()
    }
  }

  private var primaryCommitID: String?
  private var storedCommitIDs: Set<String> = []
  var selectedReflogSelector: String?
  var selectedReflogOID: ObjectID?
  var fileSelections: Set<RepositoryModel.FileSelection> = []
  var selectedPRNumber: Int?
  var historyFocus: HistoryFocus?
  var activeSheet: ActiveSheet?
  var confirmation: Confirmation?
  var deletingTag: Tag?
  var deletingRemoteTag: RemoteTagSelection?

  func present(_ sheet: ActiveSheet) {
    activeSheet = sheet
  }

  func confirm(_ confirmation: Confirmation) {
    self.confirmation = confirmation
  }

  func select(_ item: SidebarItem) {
    sidebarSelection = item
    if item == .history {
      historyFocus = nil
    }
  }

  func focusHistory(on branch: Branch) {
    historyFocus = HistoryFocus(
      tip: branch.tip,
      reference: .localBranch(branch.name)
    )
    sidebarSelection = .branch(branch.name)
  }

  func focusHistory(on branch: Branch, remoteName: String) {
    historyFocus = HistoryFocus(
      tip: branch.tip,
      reference: .remoteBranch(remote: remoteName, name: branch.name)
    )
    sidebarSelection = .remoteBranch(remote: remoteName, branch: branch.name)
  }

  func focusHistory(on tag: Tag) {
    historyFocus = HistoryFocus(
      tip: tag.target,
      reference: .tag(tag.name)
    )
    sidebarSelection = .tag(tag.name)
  }
}
