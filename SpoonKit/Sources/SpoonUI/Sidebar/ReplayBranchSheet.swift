import SpoonCore
import SwiftUI

/// Rebases a branch that is not checked out onto HEAD with `git replay`.
@MainActor
struct ReplayBranchSheet: View {
  let model: RepositoryModel
  let branch: Branch
  @Environment(\.dismiss) private var dismiss
  @State private var page: LogPage?
  @State private var loadErrorMessage: String?
  @State private var linearize = false

  var body: some View {
    SheetFormLayout(
      title: "Rebase “\(branch.name)” onto \(targetName)",
      subtitle: "The branch is rewritten in place; no files or worktrees change."
    ) {
      Group {
        if let loadErrorMessage {
          Label(loadErrorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
        } else if let page {
          content(for: page)
        } else {
          ProgressView("Finding commits to replay…")
            .frame(maxWidth: .infinity)
        }
      }
      .frame(width: 400, alignment: .leading)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Rebase", action: replay)
        .keyboardShortcut(.defaultAction)
        .disabled(!canReplay)
    }
    .task {
      do {
        page = try await model.commitsToReplay(branch)
      } catch {
        loadErrorMessage = error.localizedDescription
      }
    }
  }

  @ViewBuilder
  private func content(for page: LogPage) -> some View {
    let mergeCount = page.commits.count(where: \.isMerge)
    if page.commits.isEmpty {
      Text("“\(branch.name)” has no commits that are not already in \(targetName).")
    } else {
      Text(summary(for: page))
      if mergeCount > 0 {
        Toggle("Linearize history", isOn: $linearize)
        Text(
          "The range contains \(mergeCount == 1 ? "a merge commit" : "\(mergeCount) merge commits"). Linearizing drops merge commits and replays the commits they brought in one by one, like `git rebase` without `--rebase-merges`."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Text("If any commit conflicts, nothing is changed.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func summary(for page: LogPage) -> String {
    let count = page.hasMore ? "More than \(page.commits.count)" : "\(page.commits.count)"
    let noun = page.commits.count == 1 && !page.hasMore ? "commit" : "commits"
    return "\(count) \(noun) will be replayed onto \(targetName)."
  }

  private var targetName: String {
    model.currentBranch?.name ?? "HEAD"
  }

  private var canReplay: Bool {
    guard let page, !page.commits.isEmpty, !model.isBusy, !model.isSequencing else {
      return false
    }
    return linearize || !page.commits.contains(where: \.isMerge)
  }

  private func replay() {
    let linearize = linearize
    dismiss()
    Task { await model.replayBranchOntoHead(branch, linearize: linearize) }
  }
}
