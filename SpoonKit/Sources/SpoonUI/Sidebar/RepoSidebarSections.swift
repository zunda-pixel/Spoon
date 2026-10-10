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
  let navigation: RepositoryNavigationState
  @Bindable var expansion: SidebarExpansionState
  let searchText: String

  var body: some View {
    if !model.stashes.isEmpty {
      Section(isExpanded: $expansion.stashes) {
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
            Button("New Branch from Stash…") { navigation.present(.stashBranch(stash)) }
              .help("Apply the stash on a new branch made where it was stashed")
            Divider()
            Button("Drop…", role: .destructive) { Task { await model.dropStash(stash) } }
          }
        }
      } header: {
        Text("Stashes")
      }
      .onChange(of: searchText) {
        if searchText.hasSidebarSearchQuery {
          expansion.stashes = true
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
  let navigation: RepositoryNavigationState
  @Bindable var expansion: SidebarExpansionState
  let searchText: String

  var body: some View {
    if !model.tags.isEmpty {
      Section(isExpanded: $expansion.tags) {
        if filteredTags.isEmpty {
          Label("No matching tags", systemImage: "magnifyingglass")
            .foregroundStyle(.tertiary)
        }
        ForEach(filteredTags) { tag in
          TagSidebarRow(tag: tag, model: model, navigation: navigation)
            .contextMenu {
              TagContextMenu(
                model: model,
                tag: tag,
                navigation: navigation
              )
            }
        }
      } header: {
        Text("Tags")
      }
      .onChange(of: searchText) {
        if searchText.hasSidebarSearchQuery {
          expansion.tags = true
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

@MainActor
private struct TagSidebarRow: View {
  let tag: Tag
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  @State private var isHovered = false

  var body: some View {
    HStack(spacing: 4) {
      tagLabel
      if isHovered
        || model.isHistoryReferenceFocused(HistoryReferenceFilterID.tag(tag.name).id)
        || model.isHistoryReferenceHidden(HistoryReferenceFilterID.tag(tag.name).id) {
        HistoryReferenceFilterButtons(
          model: model,
          referenceID: HistoryReferenceFilterID.tag(tag.name).id
        )
      }
    }
    .onHover { isHovered = $0 }
    .tag(SidebarItem.tag(tag.name))
    .simultaneousGesture(
      TapGesture().onEnded {
        navigation.focusHistory(on: tag)
      }
    )
  }

  private var tagLabel: some View {
    Label {
      HStack {
        Text(tag.name)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 4)
        if tag.isSigned {
          Image(systemName: "checkmark.seal")
            .foregroundStyle(.secondary)
            .imageScale(.small)
            .accessibilityHidden(true)
        }
        Text(tag.target.shortened)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
    } icon: {
      Image(systemName: "tag")
    }
    .help("\(kind) at \(tag.target.shortened)")
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(tag.name)
    .accessibilityValue("\(kind) at commit \(tag.target.shortened)")
    .accessibilityHint("Open the context menu for tag actions")
  }

  private var kind: String {
    tag.isSigned ? "Signed tag" : tag.isAnnotated ? "Annotated tag" : "Tag"
  }
}

@MainActor
struct TagContextMenu: View {
  let model: RepositoryModel
  let tag: Tag
  let navigation: RepositoryNavigationState

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
          navigation.deletingRemoteTag = RemoteTagSelection(tag: tag, remote: remote)
        }
      }
    }
    .disabled(model.remotes.isEmpty || model.isBusy)
    Button("Export Archive…") {
      exportArchive(model: model, revision: "refs/tags/\(tag.name)", label: tag.name)
    }
    .disabled(model.isBusy)
    Divider()
    Button("Delete Tag…", role: .destructive) { navigation.deletingTag = tag }
      .disabled(model.isBusy)
  }
}
