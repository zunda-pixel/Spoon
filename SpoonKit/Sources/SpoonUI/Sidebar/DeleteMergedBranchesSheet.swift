import SpoonCore
import SwiftUI

/// Previews `git branch --delete-merged`, then deletes the listed branches.
@MainActor
struct DeleteMergedBranchesSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var branchNames: [String]?
  @State private var previewErrorMessage: String?

  var body: some View {
    SheetFormLayout(title: "Delete Merged Branches") {
      Group {
        if let previewErrorMessage {
          Label(previewErrorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
        } else if let branchNames {
          if branchNames.isEmpty {
            Text("No local branch has work that is fully merged into the upstream it tracks.")
          } else {
            Text(
              "These branches track an upstream that already contains all of their commits. Branches that push to their own upstream, are checked out, or are the base of another branch are kept."
            )
            List(branchNames, id: \.self) { name in
              Label(name, systemImage: "arrow.triangle.branch")
                .lineLimit(1)
                .truncationMode(.middle)
            }
            .frame(height: min(CGFloat(branchNames.count) * 24 + 12, 200))
            .accessibilityLabel("Branches that will be deleted")
          }
        } else {
          ProgressView("Finding merged branches…")
            .frame(maxWidth: .infinity)
        }
      }
      .frame(width: 400, alignment: .leading)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button(deleteTitle, role: .destructive, action: delete)
        .keyboardShortcut(.defaultAction)
        .disabled(branchNames?.isEmpty != false || model.isBusy)
    }
    .task {
      do {
        branchNames = try await model.mergedBranchesToDelete()
      } catch {
        previewErrorMessage = error.localizedDescription
      }
    }
  }

  private var deleteTitle: String {
    switch branchNames?.count ?? 0 {
    case 0: "Delete"
    case 1: "Delete 1 Branch"
    case let count: "Delete \(count) Branches"
    }
  }

  private func delete() {
    guard let branchNames else { return }
    dismiss()
    Task { await model.deleteMergedBranches(branchNames) }
  }
}
