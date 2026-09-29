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
    case dropLargeBlobs
    case backfill
    case fileHistory(path: String)
    case addRemote
    case addWorktree(Branch)
    case addRemoteWorktree(RemoteBranchSelection)
    case renameBranch(Branch)
    case deleteBranch(Branch)
    case deleteMergedBranches
    case deleteWorktree(Worktree)
    case renameRemoteBranch(RemoteBranchSelection)
    case mergeBranch(Branch)
    case replayBranch(Branch)
    case rebase(Commit)
    case dropCommit(Commit)
    case fixupCommit(Commit)
    case rewordCommit(Commit)
    case moveBranch(Branch, to: Commit)
    case tag(Commit)
    case reset(target: ObjectID, description: String)
    case review(ReviewReport)

    var id: String {
      switch self {
      case .newBranch(let startPoint):
        "new-branch:\(startPoint ?? "HEAD")"
      case .sparseCheckout:
        "sparse-checkout"
      case .dropLargeBlobs:
        "drop-large-blobs"
      case .backfill:
        "backfill"
      case .fileHistory(let path):
        "file-history:\(path)"
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
      case .deleteWorktree(let worktree):
        "delete-worktree:\(worktree.id)"
      case .renameRemoteBranch(let selection):
        "rename-remote-branch:\(selection.id)"
      case .mergeBranch(let branch):
        "merge-branch:\(branch.id)"
      case .replayBranch(let branch):
        "replay-branch:\(branch.id)"
      case .rebase(let commit):
        "rebase:\(commit.id)"
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
      }
    }
  }

  enum Confirmation: String, Identifiable {
    case forcePush
    case abortSequencer

    var id: Self { self }
  }

  var sidebarSelection: SidebarItem? = .changes
  var selectedCommitID: String?
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
