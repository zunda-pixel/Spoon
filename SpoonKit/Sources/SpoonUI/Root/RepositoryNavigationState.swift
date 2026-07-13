import Observation
import SpoonCore

enum SidebarItem: Hashable {
  case changes
  case history
  case reflog
  case branch(String)
  case pullRequests
  case remote(String)
  case stash(Int)
}

@MainActor
@Observable
final class RepositoryNavigationState {
  enum ActiveSheet: Hashable, Identifiable {
    case newBranch(startPoint: String?)
    case sparseCheckout
    case fileHistory(path: String)
    case addRemote
    case addWorktree(Branch)
    case renameBranch(Branch)
    case mergeBranch(Branch)
    case rebase(Commit)
    case tag(Commit)
    case reset(target: ObjectID, description: String)
    case review(ReviewReport)

    var id: String {
      switch self {
      case .newBranch(let startPoint):
        "new-branch:\(startPoint ?? "HEAD")"
      case .sparseCheckout:
        "sparse-checkout"
      case .fileHistory(let path):
        "file-history:\(path)"
      case .addRemote:
        "add-remote"
      case .addWorktree(let branch):
        "add-worktree:\(branch.id)"
      case .renameBranch(let branch):
        "rename-branch:\(branch.id)"
      case .mergeBranch(let branch):
        "merge-branch:\(branch.id)"
      case .rebase(let commit):
        "rebase:\(commit.id)"
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
  var activeSheet: ActiveSheet?
  var confirmation: Confirmation?

  func present(_ sheet: ActiveSheet) {
    activeSheet = sheet
  }

  func confirm(_ confirmation: Confirmation) {
    self.confirmation = confirmation
  }

  func select(_ item: SidebarItem) {
    sidebarSelection = item
  }
}
