import SpoonCore
import SwiftUI

@MainActor
struct RepositorySheetHost: ViewModifier {
  let model: RepositoryModel
  @Bindable var navigation: RepositoryNavigationState
  let switchToWorktree: (URL) -> Void

  func body(content: Content) -> some View {
    content.sheet(item: $navigation.activeSheet) {
      if model.reviewReport != nil {
        model.dismissReview()
      }
    } content: { sheet in
      switch sheet {
      case .newBranch(let startPoint):
        NewBranchSheet(model: model, startPoint: startPoint)
      case .sparseCheckout:
        SparseCheckoutSheet(model: model)
      case .stashChanges(let paths):
        StashChangesSheet(model: model, paths: paths)
      case .dropLargeBlobs:
        DropLargeBlobsSheet(model: model)
      case .backfill:
        BackfillSheet(model: model)
      case .fileHistory(let path):
        FileHistorySheet(model: model, path: path)
      case .blame(let path):
        BlameSheet(model: model, path: path, navigation: navigation)
      case .lineHistory(let path, let lines):
        LineHistorySheet(model: model, path: path, lines: lines, navigation: navigation)
      case .codeSearch:
        CodeSearchSheet(model: model, navigation: navigation)
      case .addRemote:
        AddRemoteSheet(model: model)
      case .addSubmodule:
        AddSubmoduleSheet(model: model)
      case .addWorktree(let branch):
        AddWorktreeSheet(
          model: model,
          branch: branch,
          switchToWorktree: switchToWorktree
        )
      case .addRemoteWorktree(let selection):
        AddRemoteBranchWorktreeSheet(
          model: model,
          selection: selection,
          switchToWorktree: switchToWorktree
        )
      case .renameBranch(let branch):
        RenameBranchSheet(model: model, branch: branch)
      case .deleteBranch(let branch):
        DeleteBranchSheet(model: model, branch: branch)
      case .deleteBranches(let branches):
        DeleteBranchesSheet(model: model, branches: branches)
      case .deleteMergedBranches:
        DeleteMergedBranchesSheet(model: model)
      case .deleteWorktree(let worktree):
        DeleteWorktreeSheet(model: model, worktree: worktree)
      case .lockWorktree(let worktree):
        LockWorktreeSheet(model: model, worktree: worktree)
      case .renameRemoteBranch(let selection):
        RenameRemoteBranchSheet(model: model, selection: selection)
      case .mergeBranch(let branch):
        MergeSheet(model: model, branch: branch)
      case .compareBranchVersions(let branch):
        RangeDiffSheet(model: model, branch: branch)
      case .replayBranch(let branch):
        ReplayBranchSheet(model: model, branch: branch)
      case .rebase(let commit):
        RebaseSheet(model: model, fromCommit: commit)
      case .autosquash:
        AutosquashSheet(model: model)
      case .startBisect(let commit):
        StartBisectSheet(model: model, goodCommit: commit)
      case .moveBranch(let branch, let commit):
        MoveBranchSheet(model: model, branch: branch, commit: commit)
      case .dropCommit(let commit):
        HistoryRewriteSheet(model: model, commit: commit, operation: .drop)
      case .fixupCommit(let commit):
        HistoryRewriteSheet(model: model, commit: commit, operation: .fixup)
      case .rewordCommit(let commit):
        RewordCommitSheet(model: model, commit: commit)
      case .tag(let commit):
        TagCommitSheet(model: model, commit: commit)
      case .reset(let target, let description):
        ResetSheet(model: model, target: target, targetDescription: description)
      case .review(let report):
        ReviewFindingsView(report: report) {
          model.dismissReview()
          navigation.activeSheet = nil
        }
      }
    }
  }
}

extension View {
  func repositorySheets(
    model: RepositoryModel,
    navigation: RepositoryNavigationState,
    switchToWorktree: @escaping (URL) -> Void
  ) -> some View {
    modifier(
      RepositorySheetHost(
        model: model,
        navigation: navigation,
        switchToWorktree: switchToWorktree
      )
    )
  }
}
