import SpoonCore
import SwiftUI

@MainActor
struct WorkspaceSidebarSection: View {
  let model: RepositoryModel

  var body: some View {
    Section("Workspace") {
      Label("Changes", systemImage: "square.and.pencil")
        .badge(model.pendingChangeCount)
        .tag(SidebarItem.changes)
        .accessibilityValue("\(model.pendingChangeCount) pending change(s)")
      Label("History", systemImage: "clock")
        .tag(SidebarItem.history)
      Label("Reflog", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
        .tag(SidebarItem.reflog)
      if model.gitHubRepoRef != nil {
        Label("Pull Requests", systemImage: "arrow.triangle.pull")
          .badge(model.openPullRequests.count)
          .tag(SidebarItem.pullRequests)
          .accessibilityValue("\(model.openPullRequests.count) open pull request(s)")
      }
    }
  }
}

@MainActor
struct StashesSidebarSection: View {
  let model: RepositoryModel
  let searchText: String
  @State private var isExpanded = true

  var body: some View {
    if !model.stashes.isEmpty {
      Section(isExpanded: $isExpanded) {
        if filteredStashes.isEmpty {
          Label("No matching stashes", systemImage: "magnifyingglass")
            .foregroundStyle(.tertiary)
        }
        ForEach(filteredStashes) { stash in
          Label {
            Text(stash.message)
              .lineLimit(1)
              .truncationMode(.tail)
          } icon: {
            Image(systemName: "tray")
          }
          .tag(SidebarItem.stash(stash.index))
          .help(stash.message)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("stash@{\(stash.index)}")
          .accessibilityValue(stash.message)
          .accessibilityHint("Select to browse this stash; open the context menu for stash actions")
          .contextMenu {
            Button("Apply") { Task { await model.applyStash(stash, pop: false) } }
            Button("Pop (Apply and Drop)") {
              Task { await model.applyStash(stash, pop: true) }
            }
            Divider()
            Button("Drop…", role: .destructive) { Task { await model.dropStash(stash) } }
          }
        }
      } header: {
        Text("Stashes")
      }
      .onChange(of: searchText) {
        if searchText.hasSidebarSearchQuery {
          isExpanded = true
        }
      }
    }
  }

  private var filteredStashes: [Stash] {
    model.stashes.filter {
      $0.message.matchesSidebarSearch(searchText)
        || $0.reference.matchesSidebarSearch(searchText)
    }
  }
}

@MainActor
struct TagsSidebarSection: View {
  let model: RepositoryModel
  @Binding var deletingTag: Tag?
  @Binding var deletingRemoteTag: RemoteTagSelection?
  let searchText: String
  @State private var isExpanded = false

  var body: some View {
    if !model.tags.isEmpty {
      Section(isExpanded: $isExpanded) {
        if filteredTags.isEmpty {
          Label("No matching tags", systemImage: "magnifyingglass")
            .foregroundStyle(.tertiary)
        }
        ForEach(filteredTags) { tag in
          TagSidebarRow(tag: tag)
            .contextMenu {
              TagContextMenu(
                model: model,
                tag: tag,
                deletingTag: $deletingTag,
                deletingRemoteTag: $deletingRemoteTag
              )
            }
        }
      } header: {
        Text("Tags")
      }
      .onChange(of: searchText) {
        if searchText.hasSidebarSearchQuery {
          isExpanded = true
        }
      }
    }
  }

  private var filteredTags: [Tag] {
    model.tags.filter {
      $0.name.matchesSidebarSearch(searchText)
        || $0.target.rawValue.matchesSidebarSearch(searchText)
    }
  }
}

private struct TagSidebarRow: View {
  let tag: Tag

  var body: some View {
    Label {
      HStack {
        Text(tag.name)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 4)
        Text(tag.target.shortened)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
    } icon: {
      Image(systemName: "tag")
    }
    .help(
      tag.isAnnotated
        ? "Annotated tag at \(tag.target.shortened)" : "Tag at \(tag.target.shortened)"
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(tag.name)
    .accessibilityValue(
      "\(tag.isAnnotated ? "Annotated tag" : "Tag") at commit \(tag.target.shortened)"
    )
    .accessibilityHint("Open the context menu for tag actions")
  }
}

@MainActor
private struct TagContextMenu: View {
  let model: RepositoryModel
  let tag: Tag
  @Binding var deletingTag: Tag?
  @Binding var deletingRemoteTag: RemoteTagSelection?

  var body: some View {
    Menu("Push to Remote") {
      ForEach(model.remotes) { remote in
        Button(remote.name) { Task { await model.pushTag(name: tag.name, to: remote.name) } }
      }
    }
    .disabled(model.remotes.isEmpty || model.isBusy)
    Menu("Delete from Remote") {
      ForEach(model.remotes) { remote in
        Button(remote.name, role: .destructive) {
          deletingRemoteTag = RemoteTagSelection(tag: tag, remote: remote)
        }
      }
    }
    .disabled(model.remotes.isEmpty || model.isBusy)
    Divider()
    Button("Delete Tag…", role: .destructive) { deletingTag = tag }
      .disabled(model.isBusy)
  }
}
