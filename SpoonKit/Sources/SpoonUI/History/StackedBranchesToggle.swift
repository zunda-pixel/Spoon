import SpoonCore
import SwiftUI

/// Whether a rebase moves the other branches in its range along
/// (`--update-refs`), such as the lower layers of a stack. Without it they
/// keep pointing at the old commits.
@MainActor
struct StackedBranchesToggle: View {
  let branches: [StackedBranch]
  @Binding var isOn: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Toggle(isOn: $isOn) {
        Text(
          branches.count == 1
            ? "Also move “\(branches[0].name)” to the rewritten commits"
            : "Also move \(branches.count) other branches to the rewritten commits"
        )
      }
      Text(
        isOn
          ? "Branches stacked in this range follow their commits (rebase --update-refs)."
          : "\(branches.map(\.name).formatted(.list(type: .and))) will keep pointing at the old commits."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.leading, 20)
    }
    .help(branches.map(\.name).joined(separator: "\n"))
  }
}

/// A branch whose tip is this commit, in a rebase plan's row.
@MainActor
struct StackedBranchBadge: View {
  let name: String
  let moves: Bool

  var body: some View {
    Label(name, systemImage: "arrow.triangle.branch")
      .font(.caption)
      .lineLimit(1)
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(.quaternary, in: Capsule())
      .foregroundStyle(moves ? .primary : .secondary)
      .help(moves ? "Moves with this commit" : "Stays on the old commit")
  }
}
