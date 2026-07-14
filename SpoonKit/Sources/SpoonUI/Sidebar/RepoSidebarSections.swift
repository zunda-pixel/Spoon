import AppKit
import SpoonCore
import SwiftUI

struct RemoteTagSelection: Identifiable {
  let tag: Tag
  let remote: Remote

  var id: String { "\(remote.name)\u{0}\(tag.name)" }
}

struct RemoteBranchSelection: Hashable, Identifiable {
  let remote: Remote
  let branch: Branch

  var fullName: String { branch.name }

  var localName: String {
    let prefix = "\(remote.name)/"
    return fullName.hasPrefix(prefix) ? String(fullName.dropFirst(prefix.count)) : fullName
  }

  var id: String { "\(remote.name)\u{0}\(branch.name)" }
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
  let searchText: String
  let openWorktree: (Worktree) -> Void
  @State private var isExpanded = true
  @State private var expandedFolderPaths: Set<String> = []

  var body: some View {
    Section(isExpanded: $isExpanded) {
      if filteredBranches.isEmpty, searchText.hasSidebarSearchQuery {
        Label("No matching branches", systemImage: "magnifyingglass")
          .foregroundStyle(.tertiary)
      }
      ForEach(BranchTreeNode.make(from: filteredBranches)) { node in
        BranchTreeNodeView(
          node: node,
          model: model,
          navigation: navigation,
          isSearching: searchText.hasSidebarSearchQuery,
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
    .onChange(of: searchText) {
      if searchText.hasSidebarSearchQuery {
        isExpanded = true
      }
    }
  }

  private var filteredBranches: [Branch] {
    model.branches.filter { branch in
      branch.name.matchesSidebarSearch(searchText)
        || branch.subject.matchesSidebarSearch(searchText)
        || branch.upstream?.matchesSidebarSearch(searchText) == true
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

  static func make(
    from branches: [Branch],
    removingPrefix prefix: String? = nil
  ) -> [BranchTreeNode] {
    var nodes: [BranchTreeNode] = []
    for branch in branches {
      let displayPath =
        if let prefix, branch.name.hasPrefix(prefix) {
          String(branch.name.dropFirst(prefix.count))
        } else {
          branch.name
        }
      insert(
        branch,
        components: displayPath.split(separator: "/")[...],
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
        BranchTreeNode(name: name, path: path, branch: branch, children: [])
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
  let isSearching: Bool
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
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .tag(SidebarItem.branch(branch.name))
      .simultaneousGesture(
        TapGesture().onEnded {
          navigation.sidebarSelection = .branch(branch.name)
        }
      )
      .simultaneousGesture(
        TapGesture(count: 2).onEnded {
          activateBranch(branch, worktree: worktree)
        }
      )
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
            isSearching: isSearching,
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

  private func activateBranch(_ branch: Branch, worktree: Worktree?) {
    navigation.sidebarSelection = .branch(branch.name)

    if let worktree {
      openWorktree(worktree)
    } else if !branch.isCurrent && !model.isBusy && !model.isSequencing {
      Task { await model.switchBranch(branch.name) }
    }
  }

  private var isFolderExpanded: Binding<Bool> {
    if isSearching {
      return .constant(true)
    }
    return Binding(
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
    Button("Switch") {
      Task { await model.switchBranch(branch.name) }
    }
    .disabled(branch.isCurrent || model.isBusy || worktree != nil)
    Divider()
    Button("Merge into \(model.currentBranch?.name ?? "HEAD")…") {
      navigation.present(.mergeBranch(branch))
    }
    .disabled(branch.isCurrent || model.isBusy || model.isSequencing)
    Divider()
    if let worktree {
      Button("Switch to Worktree") { openWorktree(worktree) }
      Button("Open in Finder") {
        NSWorkspace.shared.open(worktree.path)
      }
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

private extension String {
  var hasSidebarSearchQuery: Bool {
    !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func matchesSidebarSearch(_ searchText: String) -> Bool {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return query.isEmpty || localizedCaseInsensitiveContains(query)
  }
}

@MainActor
struct RemotesSidebarSection: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  @Binding var removingRemote: Remote?
  @Binding var removingWorktree: Worktree?
  @Binding var deletingRemoteBranch: RemoteBranchSelection?
  let searchText: String
  let openWorktree: (Worktree) -> Void
  @State private var isExpanded = true
  @State private var expandedRemoteNames: Set<String> = []
  @State private var expandedFolderPaths: Set<String> = []

  var body: some View {
    Section(isExpanded: $isExpanded) {
      if filteredRemotes.isEmpty {
        Label(
          searchText.hasSidebarSearchQuery ? "No matching remotes or branches" : "No remotes",
          systemImage: searchText.hasSidebarSearchQuery ? "magnifyingglass" : "network.slash"
        )
          .foregroundStyle(.tertiary)
          .contextMenu { addRemoteButton }
      }
      ForEach(filteredRemotes) { remote in
        DisclosureGroup(isExpanded: isRemoteExpanded(remote)) {
          ForEach(
            BranchTreeNode.make(
              from: filteredBranches(for: remote),
              removingPrefix: "\(remote.name)/"
            )
          ) { node in
            RemoteBranchTreeNodeView(
              node: node,
              remote: remote,
              model: model,
              navigation: navigation,
              isSearching: searchText.hasSidebarSearchQuery,
              expandedFolderPaths: $expandedFolderPaths,
              removingWorktree: $removingWorktree,
              deletingRemoteBranch: $deletingRemoteBranch,
              openWorktree: openWorktree
            )
          }
        } label: {
          Label(remote.name, systemImage: "network")
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .tag(SidebarItem.remote(remote.name))
            .help(remote.fetchURL)
            .simultaneousGesture(
              TapGesture().onEnded {
                navigation.sidebarSelection = .remote(remote.name)
              }
            )
            .contextMenu {
              addRemoteButton
              Divider()
              Button("Push All Tags") { Task { await model.pushAllTags(to: remote.name) } }
                .disabled(model.tags.isEmpty || model.isBusy)
              Divider()
              Button("Remove “\(remote.name)”…", role: .destructive) {
                removingRemote = remote
              }
            }
        }
      }
    } header: {
      Text("Remotes")
    }
    .onChange(of: searchText) {
      if searchText.hasSidebarSearchQuery {
        isExpanded = true
      }
    }
  }

  private var addRemoteButton: some View {
    Button("Add Remote…") { navigation.present(.addRemote) }
      .disabled(model.isBusy)
  }

  private var filteredRemotes: [Remote] {
    model.remotes.filter { remote in
      remote.name.matchesSidebarSearch(searchText)
        || remote.fetchURL.matchesSidebarSearch(searchText)
        || (remote.pushURL?.matchesSidebarSearch(searchText) == true)
        || (model.remoteBranchesByRemote[remote.name] ?? []).contains {
          branchMatchesSearch($0)
        }
    }
  }

  private func filteredBranches(for remote: Remote) -> [Branch] {
    let branches = model.remoteBranchesByRemote[remote.name] ?? []
    guard searchText.hasSidebarSearchQuery else { return branches }
    if remote.name.matchesSidebarSearch(searchText)
      || remote.fetchURL.matchesSidebarSearch(searchText)
      || remote.pushURL?.matchesSidebarSearch(searchText) == true
    {
      return branches
    }
    return branches.filter(branchMatchesSearch)
  }

  private func branchMatchesSearch(_ branch: Branch) -> Bool {
    branch.name.matchesSidebarSearch(searchText)
      || branch.subject.matchesSidebarSearch(searchText)
  }

  private func isRemoteExpanded(_ remote: Remote) -> Binding<Bool> {
    if searchText.hasSidebarSearchQuery {
      return .constant(true)
    }
    return Binding(
      get: { expandedRemoteNames.contains(remote.name) },
      set: { expanded in
        if expanded {
          expandedRemoteNames.insert(remote.name)
        } else {
          expandedRemoteNames.remove(remote.name)
        }
      }
    )
  }
}

@MainActor
private struct RemoteBranchTreeNodeView: View {
  let node: BranchTreeNode
  let remote: Remote
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  let isSearching: Bool
  @Binding var expandedFolderPaths: Set<String>
  @Binding var removingWorktree: Worktree?
  @Binding var deletingRemoteBranch: RemoteBranchSelection?
  let openWorktree: (Worktree) -> Void

  var body: some View {
    if let branch = node.branch {
      let selection = RemoteBranchSelection(remote: remote, branch: branch)
      let localBranch = model.branches.first { $0.name == selection.localName }
      let worktree = localBranch.flatMap { model.worktree(for: $0) }
      BranchRowView(
        branch: branch,
        displayName: node.name,
        pullRequest: nil,
        worktree: worktree
      )
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .tag(SidebarItem.remoteBranch(remote: remote.name, branch: branch.name))
      .simultaneousGesture(
        TapGesture().onEnded {
          navigation.sidebarSelection = .remoteBranch(
            remote: remote.name,
            branch: branch.name
          )
        }
      )
      .simultaneousGesture(
        TapGesture(count: 2).onEnded {
          activate(selection, localBranch: localBranch, worktree: worktree)
        }
      )
      .contextMenu {
        remoteBranchContextMenu(
          selection,
          localBranch: localBranch,
          worktree: worktree
        )
      }
    } else {
      DisclosureGroup(isExpanded: isFolderExpanded) {
        ForEach(node.children) { child in
          RemoteBranchTreeNodeView(
            node: child,
            remote: remote,
            model: model,
            navigation: navigation,
            isSearching: isSearching,
            expandedFolderPaths: $expandedFolderPaths,
            removingWorktree: $removingWorktree,
            deletingRemoteBranch: $deletingRemoteBranch,
            openWorktree: openWorktree
          )
        }
      } label: {
        Label(node.name, systemImage: "folder")
      }
    }
  }

  @ViewBuilder
  private func remoteBranchContextMenu(
    _ selection: RemoteBranchSelection,
    localBranch: Branch?,
    worktree: Worktree?
  ) -> some View {
    Button(worktree == nil ? "Switch" : "Switch to Worktree") {
      activate(selection, localBranch: localBranch, worktree: worktree)
    }
    .disabled(
      model.isBusy || model.isSequencing
        || (localBranch?.isCurrent == true && worktree == nil)
    )
    Divider()
    Button("Merge into \(model.currentBranch?.name ?? "HEAD")…") {
      navigation.present(.mergeBranch(selection.branch))
    }
    .disabled(model.isBusy || model.isSequencing)
    Divider()
    if let worktree {
      Button("Open in Finder") {
        NSWorkspace.shared.open(worktree.path)
      }
      if !worktree.isMain {
        Button("Remove Worktree…", role: .destructive) {
          removingWorktree = worktree
        }
        .disabled(model.isBusy)
      }
    } else if let localBranch {
      Button("Add Worktree…") {
        navigation.present(.addWorktree(localBranch))
      }
      .disabled(localBranch.isCurrent || model.isBusy)
    } else {
      Button("Add Worktree…") {
        navigation.present(.addRemoteWorktree(selection))
      }
      .disabled(model.isBusy)
    }
    Divider()
    Button("New Branch from Here…") {
      navigation.present(.newBranch(startPoint: selection.fullName))
    }
    .disabled(model.isBusy)
    Button("Rename Remote Branch…") {
      navigation.present(.renameRemoteBranch(selection))
    }
    .disabled(model.isBusy)
    Button("Delete Remote Branch…", role: .destructive) {
      deletingRemoteBranch = selection
    }
    .disabled(model.isBusy)
  }

  private func activate(
    _ selection: RemoteBranchSelection,
    localBranch: Branch?,
    worktree: Worktree?
  ) {
    navigation.sidebarSelection = .remoteBranch(
      remote: remote.name,
      branch: selection.fullName
    )
    guard !model.isBusy, !model.isSequencing else { return }

    if let worktree {
      openWorktree(worktree)
    } else if let localBranch {
      if !localBranch.isCurrent {
        Task { await model.switchBranch(localBranch.name) }
      }
    } else {
      Task { await model.switchToRemoteBranch(selection.fullName) }
    }
  }

  private var isFolderExpanded: Binding<Bool> {
    if isSearching {
      return .constant(true)
    }
    let folderID = "\(remote.name)/\(node.path)"
    return Binding(
      get: { expandedFolderPaths.contains(folderID) },
      set: { expanded in
        if expanded {
          expandedFolderPaths.insert(folderID)
        } else {
          expandedFolderPaths.remove(folderID)
        }
      }
    )
  }
}
