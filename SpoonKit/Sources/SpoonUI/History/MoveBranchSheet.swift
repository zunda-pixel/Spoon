import SpoonCore
import SwiftUI

/// Confirms repointing a branch that is not checked out at another commit.
@MainActor
struct MoveBranchSheet: View {
  let model: RepositoryModel
  let branch: Branch
  let commit: Commit
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    SheetFormLayout(
      title: "Move Branch “\(branch.name)”",
      subtitle: "\(branch.tip.shortened) → \(commit.oid.shortened) — \(commit.subject)"
    ) {
      Text(
        "The branch will point at the selected commit. No files change, because the branch is not checked out. Commits only reachable from its current tip stay recoverable from the reflog."
      )
      .frame(width: 400, alignment: .leading)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Move Branch", role: .destructive) {
        dismiss()
        Task { await model.moveBranch(branch, to: commit.oid) }
      }
      .keyboardShortcut(.defaultAction)
      .disabled(model.isBusy)
    }
  }
}
