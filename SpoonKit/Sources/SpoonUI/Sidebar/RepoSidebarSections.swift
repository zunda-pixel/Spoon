import SpoonCore
import SwiftUI

struct RemoteTagSelection: Identifiable {
  let tag: Tag
  let remote: Remote

  var id: String { "\(remote.name)\u{0}\(tag.name)" }
}

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
struct BranchesSidebarSection: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  @Binding var removingWorktree: Worktree?
  @Binding var deletingBranch: Branch?
  let openWorktree: (Worktree) -> Void
  @State private var isExpanded = true
  @State private var expandedFolderPaths: Set<String> = []

  var body: some View {
    Section(isExpanded: $isExpanded) {
      ForEach(BranchTreeNode.make(from: model.branches)) { node in
        BranchTreeNodeView(
          node: node,
          model: model,
          navigation: navigation,
          expandedFolderPaths: $expandedFolderPaths,
          removingWorktree: $removingWorktree,
          deletingBranch: $deletingBranch,
          openWorktree: openWorktree
        )
      }
    } header: {
      Text("Branches")
    }
    .onChange(of: model.currentBranch?.name, initial: true) {
      guard let currentBranchName = model.currentBranch?.name else { return }
      expandedFolderPaths.formUnion(BranchTreeNode.folderPaths(in: currentBranchName))
    }
  }
}

private struct BranchTreeNode: Identifiable {
  let name: String
  let path: String
  let branch: Branch?
  var children: [BranchTreeNode]

  var id: String {
    branch == nil ? "folder:\(path)" : "branch:\(path)"
  }

  static func make(from branches: [Branch]) -> [BranchTreeNode] {
    var nodes: [BranchTreeNode] = []
    for branch in branches {
      insert(
        branch,
        components: branch.name.split(separator: "/")[...],
        parentPath: "",
        into: &nodes
      )
    }
    return nodes.filter { $0.branch != nil } + nodes.filter { $0.branch == nil }
  }

  static func folderPaths(in branchName: String) -> Set<String> {
    let components = branchName.split(separator: "/")
    guard components.count > 1 else { return [] }

    var paths: Set<String> = []
    var path = ""
    for component in components.dropLast() {
      path = path.isEmpty ? String(component) : "\(path)/\(component)"
      paths.insert(path)
    }
    return paths
  }

  private static func insert(
    _ branch: Branch,
    components: ArraySlice<Substring>,
    parentPath: String,
    into nodes: inout [BranchTreeNode]
  ) {
    guard let component = components.first else { return }

    let name = String(component)
    let path = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
    if components.count == 1 {
      nodes.append(
        BranchTreeNode(name: name, path: branch.name, branch: branch, children: [])
      )
      return
    }

    if let index = nodes.firstIndex(where: { $0.branch == nil && $0.path == path }) {
      insert(
        branch,
        components: components.dropFirst(),
        parentPath: path,
        into: &nodes[index].children
      )
    } else {
      var folder = BranchTreeNode(name: name, path: path, branch: nil, children: [])
      insert(
        branch,
        components: components.dropFirst(),
        parentPath: path,
        into: &folder.children
      )
      nodes.append(folder)
    }
  }
}

@MainActor
private struct BranchTreeNodeView: View {
  let node: BranchTreeNode
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  @Binding var expandedFolderPaths: Set<String>
  @Binding var removingWorktree: Worktree?
  @Binding var deletingBranch: Branch?
  let openWorktree: (Worktree) -> Void

  var body: some View {
    if let branch = node.branch {
      let worktree = model.worktree(for: branch)
      BranchRowView(
        branch: branch,
        displayName: node.name,
        pullRequest: model.prByBranch[branch.name],
        worktree: worktree
      )
      .tag(SidebarItem.branch(branch.name))
      .contextMenu {
        BranchContextMenu(
          model: model,
          navigation: navigation,
          branch: branch,
          worktree: worktree,
          removingWorktree: $removingWorktree,
          deletingBranch: $deletingBranch,
          openWorktree: openWorktree
        )
      }
    } else {
      DisclosureGroup(isExpanded: isFolderExpanded) {
        ForEach(node.children) { child in
          BranchTreeNodeView(
            node: child,
            model: model,
            navigation: navigation,
            expandedFolderPaths: $expandedFolderPaths,
            removingWorktree: $removingWorktree,
            deletingBranch: $deletingBranch,
            openWorktree: openWorktree
          )
        }
      } label: {
        Label(node.name, systemImage: "folder")
      }
    }
  }

  private var isFolderExpanded: Binding<Bool> {
    Binding(
      get: { expandedFolderPaths.contains(node.path) },
      set: { isExpanded in
        if isExpanded {
          expandedFolderPaths.insert(node.path)
        } else {
          expandedFolderPaths.remove(node.path)
        }
      }
    )
  }
}

@MainActor
private struct BranchContextMenu: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  let branch: Branch
  let worktree: Worktree?
  @Binding var removingWorktree: Worktree?
  @Binding var deletingBranch: Branch?
  let openWorktree: (Worktree) -> Void

  var body: some View {
    Button("Checkout") {
      Task { await model.checkout(branch: branch.name) }
    }
    .disabled(branch.isCurrent || model.isBusy || worktree != nil)
    Divider()
    Button("Merge into \(model.currentBranch?.name ?? "HEAD")…") {
      navigation.present(.mergeBranch(branch))
    }
    .disabled(branch.isCurrent || model.isBusy || model.isSequencing)
    Divider()
    if let worktree {
      Button("Open Worktree") { openWorktree(worktree) }
      if !worktree.isMain {
        Button("Remove Worktree…", role: .destructive) { removingWorktree = worktree }
          .disabled(model.isBusy)
      }
    } else if !branch.isCurrent {
      Button("Add Worktree…") { navigation.present(.addWorktree(branch)) }
        .disabled(model.isBusy)
    }
    Divider()
    Button("New Branch from Here…") {
      navigation.present(.newBranch(startPoint: branch.name))
    }
    .disabled(model.isBusy)
    Button("Rename Branch…") { navigation.present(.renameBranch(branch)) }
      .disabled(model.isBusy)
    Button("Delete Branch…", role: .destructive) { deletingBranch = branch }
      .disabled(branch.isCurrent || model.isBusy || worktree != nil)
  }
}

@MainActor
struct StashesSidebarSection: View {
  let model: RepositoryModel
  @State private var isExpanded = true

  var body: some View {
    if !model.stashes.isEmpty {
      Section(isExpanded: $isExpanded) {
        ForEach(model.stashes) { stash in
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
    }
  }
}

@MainActor
struct TagsSidebarSection: View {
  let model: RepositoryModel
  @Binding var deletingTag: Tag?
  @Binding var deletingRemoteTag: RemoteTagSelection?
  @State private var isExpanded = true

  var body: some View {
    if !model.tags.isEmpty {
      Section(isExpanded: $isExpanded) {
        ForEach(model.tags) { tag in
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

@MainActor
struct RemotesSidebarSection: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  @Binding var removingRemote: Remote?
  @State private var isExpanded = true

  var body: some View {
    Section(isExpanded: $isExpanded) {
      if model.remotes.isEmpty {
        Label("No remotes", systemImage: "network.slash")
          .foregroundStyle(.tertiary)
          .contextMenu { addRemoteButton }
      }
      ForEach(model.remotes) { remote in
        Label(remote.name, systemImage: "network")
          .tag(SidebarItem.remote(remote.name))
          .help(remote.fetchURL)
          .contextMenu {
            addRemoteButton
            Divider()
            Button("Push All Tags") { Task { await model.pushAllTags(to: remote.name) } }
              .disabled(model.tags.isEmpty || model.isBusy)
            Divider()
            Button("Remove “\(remote.name)”…", role: .destructive) { removingRemote = remote }
          }
      }
    } header: {
      Text("Remotes")
    }
  }

  private var addRemoteButton: some View {
    Button("Add Remote…") { navigation.present(.addRemote) }
      .disabled(model.isBusy)
  }
}
