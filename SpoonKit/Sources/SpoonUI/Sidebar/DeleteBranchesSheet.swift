import SpoonCore
import SwiftUI

/// Deletes several local branches at once, with the same force and
/// remote-branch choices as the single-branch sheet.
@MainActor
struct DeleteBranchesSheet: View {
  let model: RepositoryModel
  let branches: [Branch]
  @Environment(\.dismiss) private var dismiss
  @State private var unmergedNames: Set<String>?
  @State private var forceDelete = false
  @State private var deleteRemoteBranches = false

  var body: some View {
    SheetFormLayout(title: "Delete \(deletable.count) Branches") {
      List(branches) { branch in
        HStack(spacing: 8) {
          Label(branch.name, systemImage: "arrow.triangle.branch")
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          if let reason = skipReason(branch) {
            Text(reason)
              .font(.caption)
              .foregroundStyle(.secondary)
          } else if unmergedNames?.contains(branch.name) == true {
            Text("Unmerged")
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }
      }
      .frame(width: 420, height: min(CGFloat(branches.count) * 28 + 16, 220))
      .accessibilityLabel("Branches to delete")

      if unmergedCount > 0 {
        Toggle(
          "Force delete \(unmergedCount) unmerged \(unmergedCount == 1 ? "branch" : "branches"), discarding their commits",
          isOn: $forceDelete
        )
      }
      if unmergedCount > 0, !forceDelete {
        Text("Unmerged branches are kept unless force delete is on.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if remoteCount > 0 {
        Toggle(
          "Also delete \(remoteCount) remote \(remoteCount == 1 ? "branch" : "branches")",
          isOn: $deleteRemoteBranches
        )
        Text("This runs multiple Git operations and cannot be completed atomically.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Delete", role: .destructive, action: delete)
        .keyboardShortcut(.defaultAction)
        .disabled(
          unmergedNames == nil || deletable.isEmpty || model.isBusy
            || (unmergedCount > 0 && !forceDelete && mergedDeletable.isEmpty)
        )
    }
    .task {
      var unmerged: Set<String> = []
      for branch in deletable where await model.requiresForceDelete(branch) {
        unmerged.insert(branch.name)
      }
      unmergedNames = unmerged
    }
  }

  /// The current branch and branches checked out in a worktree cannot be deleted.
  private func skipReason(_ branch: Branch) -> String? {
    if branch.isCurrent { return "Current branch — skipped" }
    if model.worktree(for: branch) != nil { return "In a worktree — skipped" }
    return nil
  }

  private var deletable: [Branch] { branches.filter { skipReason($0) == nil } }

  private var unmergedCount: Int {
    deletable.count { unmergedNames?.contains($0.name) == true }
  }

  private var mergedDeletable: [Branch] {
    deletable.filter { unmergedNames?.contains($0.name) != true }
  }

  private var remoteCount: Int {
    deletable.count { model.existingRemoteUpstream(of: $0) != nil }
  }

  private func delete() {
    // Without force, unmerged branches are left alone rather than failing
    // the whole batch.
    let targets = forceDelete ? deletable : mergedDeletable
    let deletions = targets.map { branch in
      RepositoryModel.BranchDeletion(
        name: branch.name,
        force: unmergedNames?.contains(branch.name) == true,
        remoteUpstream: deleteRemoteBranches ? model.existingRemoteUpstream(of: branch) : nil
      )
    }
    dismiss()
    Task { await model.deleteBranches(deletions) }
  }
}
