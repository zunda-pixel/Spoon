import SpoonCore
import SwiftUI

@MainActor
struct RepositorySheetHost: ViewModifier {
  let model: RepositoryModel
  @Bindable var navigation: RepositoryNavigationState

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
      case .fileHistory(let path):
        FileHistorySheet(model: model, path: path)
      case .addRemote:
        AddRemoteSheet(model: model)
      case .addWorktree(let branch):
        AddWorktreeSheet(model: model, branch: branch)
      case .addRemoteWorktree(let selection):
        AddRemoteBranchWorktreeSheet(model: model, selection: selection)
      case .renameBranch(let branch):
        RenameBranchSheet(model: model, branch: branch)
      case .renameRemoteBranch(let selection):
        RenameRemoteBranchSheet(model: model, selection: selection)
      case .mergeBranch(let branch):
        MergeSheet(model: model, branch: branch)
      case .rebase(let commit):
        RebaseSheet(model: model, fromCommit: commit)
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
    navigation: RepositoryNavigationState
  ) -> some View {
    modifier(RepositorySheetHost(model: model, navigation: navigation))
  }
}
