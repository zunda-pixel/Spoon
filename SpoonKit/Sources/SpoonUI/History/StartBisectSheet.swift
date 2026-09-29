import SpoonCore
import SwiftUI

/// Starts `git bisect` with the checked-out commit as bad and a chosen
/// earlier commit as good.
@MainActor
struct StartBisectSheet: View {
  let model: RepositoryModel
  let goodCommit: Commit
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    SheetFormLayout(title: "Find the Commit That Introduced a Problem") {
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
        GridRow {
          Text("Bad (has the problem)")
            .foregroundStyle(.secondary)
          Text(badDescription)
        }
        GridRow {
          Text("Good (works)")
            .foregroundStyle(.secondary)
          Text("\(goodCommit.oid.shortened) — \(goodCommit.subject)")
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
      .frame(width: 440, alignment: .leading)
      Text(explanation)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 440, alignment: .leading)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Start Bisect") {
        let good = goodCommit.oid
        dismiss()
        Task { await model.startBisect(good: good) }
      }
      .keyboardShortcut(.defaultAction)
      .disabled(model.isBusy || model.isSequencing || model.status?.isClean == false)
    }
  }

  private var badDescription: String {
    let branch = model.currentBranch?.name ?? "HEAD"
    guard let head = model.status?.headOID else { return branch }
    return "\(branch) at \(head.shortened)"
  }

  private var explanation: String {
    var text =
      "Git checks out commits between the two for you to test, halving the range with each mark."
    if model.status?.isClean == false {
      text += " Commit or stash your changes first."
    }
    if model.gitCapabilities.supportsBisectResetWhenFound {
      text += " When the culprit is found, your original checkout is restored automatically."
    }
    return text
  }
}
