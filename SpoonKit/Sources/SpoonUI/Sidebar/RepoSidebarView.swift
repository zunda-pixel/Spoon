import SpoonCore
import SwiftUI

@MainActor
struct RepoSidebarView: View {
  let model: RepositoryModel
  @Binding var selection: SidebarItem?

  var body: some View {
    List(selection: $selection) {
      Section("Workspace") {
        Label("Changes", systemImage: "square.and.pencil")
          .badge(model.pendingChangeCount)
          .tag(SidebarItem.changes)
        Label("History", systemImage: "clock")
          .tag(SidebarItem.history)
        if model.gitHubRepoRef != nil {
          Label("Pull Requests", systemImage: "arrow.triangle.pull")
            .badge(model.openPullRequests.count)
            .tag(SidebarItem.pullRequests)
        }
      }

      Section("Branches") {
        ForEach(model.branches) { branch in
          BranchRowView(branch: branch, pullRequest: model.prByBranch[branch.name])
            .tag(SidebarItem.branch(branch.name))
            .contextMenu {
              Button("Checkout") {
                Task { await model.checkout(branch: branch.name) }
              }
              .disabled(branch.isCurrent || model.isBusy)
            }
        }
      }

      if !model.stashes.isEmpty {
        Section("Stashes") {
          ForEach(model.stashes) { stash in
            Label {
              Text(stash.message)
                .lineLimit(1)
                .truncationMode(.tail)
            } icon: {
              Image(systemName: "tray")
            }
            .help(stash.message)
            .contextMenu {
              Button("Apply") {
                Task { await model.applyStash(stash, pop: false) }
              }
              Button("Pop (Apply and Drop)") {
                Task { await model.applyStash(stash, pop: true) }
              }
              Divider()
              Button("Drop…", role: .destructive) {
                Task { await model.dropStash(stash) }
              }
            }
          }
        }
      }

      if !model.remotes.isEmpty {
        Section("Remotes") {
          ForEach(model.remotes) { remote in
            Label(remote.name, systemImage: "network")
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .listStyle(.sidebar)
  }
}

@MainActor
struct BranchRowView: View {
  let branch: Branch
  var pullRequest: PullRequest?

  var body: some View {
    Label {
      HStack(spacing: 4) {
        Text(branch.name)
          .fontWeight(branch.isCurrent ? .semibold : .regular)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 4)
        if let pullRequest {
          PRBadgeView(pullRequest: pullRequest)
        }
        trackingIndicator
      }
    } icon: {
      Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "arrow.trianglehead.branch")
        .foregroundStyle(branch.isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }
    .help(branch.subject)
  }

  @ViewBuilder
  private var trackingIndicator: some View {
    if branch.upstreamGone {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(.orange)
        .help("Upstream branch is gone")
    } else if (branch.ahead ?? 0) > 0 || (branch.behind ?? 0) > 0 {
      HStack(spacing: 2) {
        if let ahead = branch.ahead, ahead > 0 {
          Text("↑\(ahead)")
        }
        if let behind = branch.behind, behind > 0 {
          Text("↓\(behind)")
        }
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
    }
  }
}
