import SpoonCore
import SwiftUI

/// Confirms `git history drop` after a dry run shows which branches move.
@MainActor
struct DropCommitSheet: View {
  let model: RepositoryModel
  let commit: Commit
  @Environment(\.dismiss) private var dismiss
  @State private var updates: [RefUpdate]?
  @State private var previewErrorMessage: String?

  var body: some View {
    SheetFormLayout(
      title: "Drop Commit \(commit.oid.shortened)",
      subtitle: commit.subject
    ) {
      Group {
        if let previewErrorMessage {
          Label(previewErrorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
        } else if let updates {
          Text(explanation(for: updates))
          if !updates.isEmpty {
            List(updates) { update in
              Text(update.branchName ?? update.reference)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            .frame(height: min(CGFloat(updates.count) * 24 + 12, 160))
            .accessibilityLabel("Branches that will be rewritten")
          }
        } else {
          ProgressView("Checking which branches will change…")
            .frame(maxWidth: .infinity)
        }
      }
      .frame(width: 400, alignment: .leading)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Drop Commit", role: .destructive, action: drop)
        .keyboardShortcut(.defaultAction)
        .disabled(updates == nil || model.isBusy || model.isSequencing)
    }
    .task {
      do {
        updates = try await model.previewDropCommit(commit.oid)
      } catch {
        previewErrorMessage = error.localizedDescription
      }
    }
  }

  private func explanation(for updates: [RefUpdate]) -> String {
    if updates.isEmpty {
      return "No branch contains this commit, so dropping it changes nothing."
    }
    return
      "The commit is removed and every later commit is replayed onto its parent. These branches will be rewritten; the previous commits stay reachable from the reflog."
  }

  private func drop() {
    dismiss()
    Task { await model.dropCommit(commit.oid) }
  }
}
