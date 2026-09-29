import SpoonCore
import SwiftUI

/// Lists the fixup commits on the current branch and folds them into their
/// targets with `git rebase -i --autosquash`.
@MainActor
struct AutosquashSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var loadState: AsyncLoadState<AutosquashPlan> = .loading

  var body: some View {
    SheetFormLayout(title: "Autosquash Fixup Commits") {
      Group {
        switch loadState {
        case .loading:
          ProgressView("Finding fixup commits…")
            .frame(maxWidth: .infinity)
        case .failed(let message):
          Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
        case .loaded(let plan) where plan.fixups.isEmpty:
          Text(
            "No fixup!, squash!, or amend! commits since “\(model.currentBranch?.name ?? "HEAD")” left \(plan.baseReference)."
          )
        case .loaded(let plan):
          Text(
            "These commits are folded into the commits they name. Every commit after \(plan.base.shortened) (where the branch left \(plan.baseReference)) is rewritten."
          )
          List(plan.fixups) { commit in
            HStack(spacing: 8) {
              Text(commit.oid.shortened)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
              Text(commit.subject)
                .lineLimit(1)
                .truncationMode(.tail)
            }
          }
          .frame(height: min(CGFloat(plan.fixups.count) * 24 + 16, 200))
          .accessibilityLabel("Fixup commits")
          Text("If a commit conflicts, the rebase pauses so you can resolve it.")
            .font(.caption)
            .foregroundStyle(.secondary)
          if model.status?.isClean == false {
            Label("Commit or stash your changes first.", systemImage: "exclamationmark.triangle")
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }
      }
      .frame(width: 440, alignment: .leading)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Autosquash", action: run)
        .keyboardShortcut(.defaultAction)
        .disabled(!canRun)
    }
    .task {
      do {
        loadState = .loaded(try await model.autosquashPlan())
      } catch {
        loadState = .failed(error.localizedDescription)
      }
    }
  }

  private var canRun: Bool {
    guard case .loaded(let plan) = loadState else { return false }
    return !plan.fixups.isEmpty && !model.isBusy && !model.isSequencing
      && model.status?.isClean != false
  }

  private func run() {
    guard case .loaded(let plan) = loadState else { return }
    dismiss()
    Task { await model.autosquash(plan) }
  }
}
