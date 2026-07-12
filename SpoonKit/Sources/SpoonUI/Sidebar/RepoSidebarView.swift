import SpoonCore
import SwiftUI

@MainActor
struct RepoSidebarView: View {
  let model: RepositoryModel
  @Binding var selection: SidebarItem?
  @State private var showingAddRemoteSheet = false
  @State private var removingRemote: Remote?

  init(model: RepositoryModel, selection: Binding<SidebarItem?>) {
    self.model = model
    self._selection = selection
  }

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

      Section("Remotes") {
        if model.remotes.isEmpty {
          Label("No remotes", systemImage: "network.slash")
            .foregroundStyle(.tertiary)
            .contextMenu {
              addRemoteButton
            }
        }
        ForEach(model.remotes) { remote in
          Label(remote.name, systemImage: "network")
            .tag(SidebarItem.remote(remote.name))
            .help(remote.fetchURL)
            .contextMenu {
              addRemoteButton
              Divider()
              Button("Remove \"\(remote.name)\"…", role: .destructive) {
                removingRemote = remote
              }
            }
        }
      }
    }
    .listStyle(.sidebar)
    .sheet(isPresented: $showingAddRemoteSheet) {
      AddRemoteSheet(model: model)
    }
    .confirmationDialog(
      "Remove remote \"\(removingRemote?.name ?? "")\"?",
      isPresented: .init(
        get: { removingRemote != nil },
        set: { if !$0 { removingRemote = nil } }
      )
    ) {
      Button("Remove Remote", role: .destructive) {
        guard let remote = removingRemote else { return }
        Task { await model.removeRemote(name: remote.name) }
      }
    } message: {
      Text("Remote-tracking branches and settings for this remote will be deleted.")
    }
  }

  private var addRemoteButton: some View {
    Button("Add Remote…") {
      showingAddRemoteSheet = true
    }
    .disabled(model.isBusy)
  }
}

@MainActor
struct AddRemoteSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var url = ""

  init(model: RepositoryModel) {
    self.model = model
    // The conventional first remote name.
    self._name = State(initialValue: model.remotes.isEmpty ? "origin" : "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Add Remote")
        .font(.headline)
      Form {
        TextField("Name", text: $name, prompt: Text("origin"))
        TextField("URL", text: $url, prompt: Text("https://github.com/owner/repo.git"))
          .onSubmit(add)
      }
      .textFieldStyle(.roundedBorder)
      .frame(width: 360)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Button("Add", action: add)
          .keyboardShortcut(.defaultAction)
          .disabled(!isValid)
      }
    }
    .padding(20)
  }

  private var isValid: Bool {
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    let trimmedURL = url.trimmingCharacters(in: .whitespaces)
    return !trimmedName.isEmpty && !trimmedName.contains(" ")
      && !trimmedURL.isEmpty
      && !model.remotes.contains { $0.name == trimmedName }
  }

  private func add() {
    guard isValid else { return }
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    let trimmedURL = url.trimmingCharacters(in: .whitespaces)
    dismiss()
    Task { await model.addRemote(name: trimmedName, url: trimmedURL) }
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
