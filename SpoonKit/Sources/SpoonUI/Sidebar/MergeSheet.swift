import SpoonCore
import SwiftUI

@MainActor
struct MergeSheet: View {
  let model: RepositoryModel
  let branch: Branch
  @Environment(\.dismiss) private var dismiss
  @State private var options = MergeOptions.standard

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Merge “\(branch.name)”")
        .font(.headline)
      Text("Into \(model.currentBranch?.name ?? "HEAD")")
        .foregroundStyle(.secondary)

      Form {
        Picker("Commit behavior", selection: $options.commitMode) {
          Text("Automatic").tag(MergeOptions.CommitMode.automatic)
          Text("Fast-forward only").tag(MergeOptions.CommitMode.fastForwardOnly)
          Text("Always create merge commit").tag(MergeOptions.CommitMode.createMergeCommit)
          Text("Squash changes").tag(MergeOptions.CommitMode.squash)
        }

        Picker("Strategy", selection: $options.strategy) {
          Text("Automatic").tag(MergeOptions.Strategy.automatic)
          Text("ort").tag(MergeOptions.Strategy.ort)
          Text("recursive").tag(MergeOptions.Strategy.recursive)
          Text("resolve").tag(MergeOptions.Strategy.resolve)
          Text("octopus").tag(MergeOptions.Strategy.octopus)
          Text("ours").tag(MergeOptions.Strategy.ours)
          Text("subtree").tag(MergeOptions.Strategy.subtree)
        }
        .disabled(options.commitMode == .fastForwardOnly)

        Picker("Conflict preference", selection: $options.conflictPreference) {
          Text("Ask on conflicts").tag(MergeOptions.ConflictPreference.automatic)
          Text("Prefer ours").tag(MergeOptions.ConflictPreference.ours)
          Text("Prefer theirs").tag(MergeOptions.ConflictPreference.theirs)
        }
        .disabled(
          options.commitMode == .fastForwardOnly
            || options.strategy == .ours
        )
      }
      .frame(width: 420)

      Text(optionDescription)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 420, alignment: .leading)

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Button("Merge") {
          let options = options
          dismiss()
          Task { await model.merge(branch: branch.name, options: options) }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(model.isBusy || model.isSequencing)
      }
    }
    .padding(20)
  }

  private var optionDescription: String {
    if options.commitMode == .fastForwardOnly {
      return "The merge fails without changing the repository if a fast-forward is not possible."
    }
    if options.strategy == .ours {
      return "The “ours” strategy keeps the current tree and ignores all changes from the merged branch."
    }
    if options.conflictPreference != .automatic {
      return "The preference applies only to conflicting hunks; non-conflicting changes from both branches remain."
    }
    if options.commitMode == .squash {
      return "Changes are staged together without creating a commit."
    }
    return "Automatic uses Git’s default strategy and fast-forward behavior."
  }
}
