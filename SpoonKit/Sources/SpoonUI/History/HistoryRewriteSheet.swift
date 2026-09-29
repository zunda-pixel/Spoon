import SpoonCore
import SwiftUI

/// A `git history` rewrite that can be previewed with `--dry-run`.
enum HistoryRewriteOperation: Hashable {
  case drop
  case fixup

  var actionTitle: String {
    switch self {
    case .drop: "Drop Commit"
    case .fixup: "Fixup Commit"
    }
  }

  var explanation: String {
    switch self {
    case .drop:
      "The commit is removed and every later commit is replayed onto its parent."
    case .fixup:
      "The staged changes are folded into this commit, keeping its message, and every later commit is replayed on top."
    }
  }

  var noBranchesExplanation: String {
    switch self {
    case .drop: "No branch contains this commit, so dropping it changes nothing."
    case .fixup: "No branch contains this commit, so the fixup changes nothing."
    }
  }
}

/// Confirms a `git history` rewrite after a dry run shows which branches move.
@MainActor
struct HistoryRewriteSheet: View {
  let model: RepositoryModel
  let commit: Commit
  let operation: HistoryRewriteOperation
  @Environment(\.dismiss) private var dismiss
  @State private var updates: [RefUpdate]?
  @State private var previewErrorMessage: String?

  var body: some View {
    SheetFormLayout(
      title: "\(operation.actionTitle) \(commit.oid.shortened)",
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
      Button(operation.actionTitle, role: .destructive, action: apply)
        .keyboardShortcut(.defaultAction)
        .disabled(updates == nil || model.isBusy || model.isSequencing)
    }
    .task {
      do {
        updates =
          switch operation {
          case .drop: try await model.previewDropCommit(commit.oid)
          case .fixup: try await model.previewFixupCommit(commit.oid)
          }
      } catch {
        previewErrorMessage = error.localizedDescription
      }
    }
  }

  private func explanation(for updates: [RefUpdate]) -> String {
    if updates.isEmpty {
      return operation.noBranchesExplanation
    }
    return operation.explanation
      + " These branches will be rewritten; the previous commits stay reachable from the reflog."
  }

  private func apply() {
    let operation = operation
    let oid = commit.oid
    dismiss()
    Task {
      switch operation {
      case .drop: await model.dropCommit(oid)
      case .fixup: await model.fixupCommit(oid)
      }
    }
  }
}
