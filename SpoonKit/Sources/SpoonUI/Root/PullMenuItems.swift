import SpoonCore
import SwiftUI

/// Pull variants shared by the toolbar menu and the Repository menu.
@MainActor
struct PullMenuItems: View {
  @Bindable var model: RepositoryModel

  var body: some View {
    Button("Pull with Rebase") {
      Task { await model.pull(.rebase) }
    }
    Button("Pull with Merge") {
      Task { await model.pull(.merge) }
    }
    Button("Pull Fast-Forward Only") {
      Task { await model.pull(.fastForwardOnly) }
    }
    Divider()
    Toggle("Stash Local Changes Automatically", isOn: $model.pullAutostash)
      .help("Stash uncommitted changes before pulling and reapply them afterwards")
  }
}
