import OrderedCollections
import SpoonCore
import SwiftUI

@MainActor
struct RepositoryWindowRoot: View {
  let repositoryID: Repository.ID
  let switchRepository: (Repository.ID) -> Void

  @Environment(AppModel.self) private var appModel
  /// Least recently used first.
  @State private var cachedModels: OrderedDictionary<Repository.ID, RepositoryModel> = [:]
  @State private var activeModel: RepositoryModel?
  @State private var loadErrorMessage: String?
  @State private var navigations = NavigationStateCache()

  var body: some View {
    Group {
      // While another worktree's model loads, keep showing the current one
      // so the window, split view, and toolbar stay up instead of being
      // torn down and rebuilt on every switch.
      if let model = cachedModels[repositoryID] ?? activeModel, loadErrorMessage == nil {
        RepositorySplitView(
          model: model,
          navigation: navigations.state(for: model.repository.id),
          isSwitching: cachedModels[repositoryID] == nil,
          switchRepository: switchRepository
        )
      } else if let loadErrorMessage {
        ContentUnavailableView(
          "Could Not Open Repository",
          systemImage: "exclamationmark.triangle",
          description: Text(loadErrorMessage)
        )
      } else {
        ProgressView()
      }
    }
    .navigationTitle(windowTitle)
    .task(id: repositoryID) {
      await load()
    }
    .onDisappear {
      for model in cachedModels.values {
        model.stopWatching()
      }
    }
  }

  private var repositoryURL: URL {
    URL(filePath: repositoryID, directoryHint: .isDirectory)
  }

  private var windowTitle: String {
    guard let model = cachedModels[repositoryID] else {
      return Repository(rootURL: repositoryURL).name
    }
    return model.commonWorktreeName
  }

  private func load() async {
    loadErrorMessage = nil
    if activeModel?.repository.id != repositoryID {
      activeModel?.stopWatching()
    }

    if let cachedModel = cachedModels[repositoryID] {
      touchCacheEntry(repositoryID)
      cachedModel.startWatching()
      activeModel = cachedModel
      await cachedModel.refreshGitState()
      guard !Task.isCancelled, activeModel === cachedModel else { return }
      await cachedModel.syncPullRequests()
      return
    }

    do {
      let model = try await appModel.makeRepositoryModel(for: Repository(rootURL: repositoryURL))
      await model.refreshGitState()
      guard !Task.isCancelled else { return }
      insertIntoCache(model)
      model.startWatching()
      activeModel = model
      await model.syncPullRequests()
    } catch {
      loadErrorMessage = error.localizedDescription
    }
  }

  /// Moves `id` to the most recently used end.
  private func touchCacheEntry(_ id: Repository.ID) {
    guard let model = cachedModels.removeValue(forKey: id) else { return }
    cachedModels[id] = model
  }

  private func insertIntoCache(_ model: RepositoryModel) {
    let id = model.repository.id
    cachedModels.removeValue(forKey: id)
    cachedModels[id] = model

    while cachedModels.count > 6 {
      let (evictedID, evictedModel) = cachedModels.removeFirst()
      evictedModel.stopWatching()
      navigations.remove(evictedID)
    }
  }
}

/// Navigation state per repository, kept while its model is cached, so
/// switching worktrees comes back to where each one was left.
@MainActor
final class NavigationStateCache {
  private var states: [Repository.ID: RepositoryNavigationState] = [:]

  func state(for id: Repository.ID) -> RepositoryNavigationState {
    if let state = states[id] { return state }
    let state = RepositoryNavigationState()
    states[id] = state
    return state
  }

  func remove(_ id: Repository.ID) {
    states[id] = nil
  }
}

@MainActor
struct RepositorySplitView: View {
  let model: RepositoryModel
  @Bindable var navigation: RepositoryNavigationState
  /// Another worktree's model is loading; this one stays on screen until
  /// it is ready.
  let isSwitching: Bool
  let switchRepository: (Repository.ID) -> Void
  @State private var switchWorktreeErrorMessage: String?
  @State private var sidebarExpansion = SidebarExpansionState()

  var body: some View {
    // The split view and toolbar persist across worktree switches; each
    // column's contents are keyed by repository so per-view state (search
    // text, confirmations, loaded diffs) never carries over. Sidebar
    // expansion is the exception: worktrees share their branches, so it
    // lives here and folders stay as the user left them.
    NavigationSplitView {
      RepoSidebarView(
        model: model,
        navigation: navigation,
        expansion: sidebarExpansion,
        openWorktree: { switchToWorktree(at: $0.path) }
      )
      .id(model.repository.id)
      .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    } content: {
      RepositoryContentColumn(
        model: model,
        navigation: navigation,
        openWorktree: { switchToWorktree(at: $0.path) }
      )
      .id(model.repository.id)
      .overlay {
        if isSwitching {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background.opacity(0.6))
        }
      }
      // Inset the column itself: split view columns extend under the
      // toolbar and the floating sidebar, so a window-level inset overlapped
      // the sidebar and the toolbar area.
      .safeAreaInset(edge: .top, spacing: 0) {
        VStack(spacing: 0) {
          if let state = model.sequencerState {
            SequencerBannerView(model: model, state: state)
          }
          if let state = model.bisectState {
            BisectBannerView(model: model, state: state, navigation: navigation)
          }
        }
      }
      .navigationSplitViewColumnWidth(min: 300, ideal: 380)
    } detail: {
      RepositoryDetailColumn(model: model, navigation: navigation)
        .id(model.repository.id)
    }
    .alert(
      "First Bad Commit Found",
      isPresented: .init(
        get: { model.bisectResult != nil && !model.isBisecting },
        set: { if !$0 { model.dismissBisectResult() } }
      )
    ) {
      Button("Show in History") {
        if let culprit = model.bisectResult {
          navigation.select(.history)
          navigation.selectedCommitID = culprit.rawValue
        }
        model.dismissBisectResult()
      }
      Button("OK", role: .cancel) { model.dismissBisectResult() }
    } message: {
      Text(bisectResultMessage)
    }
    .navigationTitle(model.commonWorktreeName)
    .navigationSubtitle(model.repository.rootURL.path(percentEncoded: false))
    .navigationDocument(model.repository.rootURL)
    .toolbar {
      RepositoryToolbar(model: model, navigation: navigation)
    }
    .repositorySheets(
      model: model,
      navigation: navigation,
      switchToWorktree: switchToWorktree
    )
    .confirmationDialog(
      "Force push \(model.currentBranch?.name ?? "the current branch")?",
      isPresented: .init(
        get: { navigation.confirmation == .forcePush },
        set: { if !$0 { navigation.confirmation = nil } }
      )
    ) {
      Button("Force Push with Lease", role: .destructive) {
        Task { await model.push(force: true) }
      }
    } message: {
      Text(
        "This rewrites the remote branch history. The push will be refused if the remote changed since your last fetch."
      )
    }
    .confirmationDialog(
      "Abort \(sequencerName)?",
      isPresented: .init(
        get: { navigation.confirmation == .abortSequencer },
        set: { if !$0 { navigation.confirmation = nil } }
      )
    ) {
      Button("Abort \(sequencerName)", role: .destructive) {
        Task { await model.abortSequencer() }
      }
    } message: {
      Text("All progress from this operation will be discarded and the branch restored.")
    }
    .confirmationDialog(
      "Delete tag “\(navigation.deletingTag?.name ?? "")”?",
      isPresented: .init(
        get: { navigation.deletingTag != nil },
        set: { if !$0 { navigation.deletingTag = nil } }
      )
    ) {
      Button("Delete Tag", role: .destructive) {
        guard let tag = navigation.deletingTag else { return }
        Task { await model.deleteTag(name: tag.name) }
      }
    } message: {
      Text("The tag will be removed locally. Remote copies are not affected.")
    }
    .confirmationDialog(
      "Delete tag “\(navigation.deletingRemoteTag?.tag.name ?? "")” from \(navigation.deletingRemoteTag?.remote.name ?? "remote")?",
      isPresented: .init(
        get: { navigation.deletingRemoteTag != nil },
        set: { if !$0 { navigation.deletingRemoteTag = nil } }
      )
    ) {
      Button("Delete from Remote", role: .destructive) {
        guard let selection = navigation.deletingRemoteTag else { return }
        Task {
          await model.deleteRemoteTag(name: selection.tag.name, from: selection.remote.name)
        }
      }
    } message: {
      Text("The local tag will be kept.")
    }
    .alert(
      "AI Task Failed",
      isPresented: .init(
        get: { model.aiErrorMessage != nil },
        set: { if !$0 { model.clearAIError() } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.aiErrorMessage ?? "")
    }
    .alert(
      "Operation Failed",
      isPresented: .init(
        get: { model.lastErrorMessage != nil && model.status != nil },
        set: { if !$0 { model.clearError() } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.lastErrorMessage ?? "")
    }
    .alert(
      "Could Not Switch Worktree",
      isPresented: .init(
        get: { switchWorktreeErrorMessage != nil },
        set: { if !$0 { switchWorktreeErrorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(switchWorktreeErrorMessage ?? "")
    }
    .focusedSceneValue(\.repositoryModel, model)
    .focusedSceneValue(\.repositoryNavigationState, navigation)
    .onChange(of: model.branches) {
      resetStaleSidebarSelection()
    }
    .onChange(of: model.remoteBranchesByRemote) {
      resetStaleSidebarSelection()
    }
  }

  /// Moves the selection to HEAD history when the branch it pointed at
  /// disappears (e.g. it was just deleted), so the content column never
  /// keeps showing a dead reference.
  private func resetStaleSidebarSelection() {
    switch navigation.sidebarSelection {
    case .branch(let name):
      if !model.branches.contains(where: { $0.name == name }) {
        navigation.sidebarSelection = .history
      }
    case .remoteBranch(let remote, let branch):
      let remoteBranches = model.remoteBranchesByRemote[remote] ?? []
      if !remoteBranches.contains(where: { $0.name == branch }) {
        navigation.sidebarSelection = .history
      }
    default:
      break
    }
  }

  private var sequencerName: String {
    switch model.sequencerState?.kind {
    case .rebase: "Rebase"
    case .cherryPick: "Cherry-Pick"
    case .revert: "Revert"
    case .merge: "Merge"
    case .applyingPatches: "Patch Application"
    case nil: "Operation"
    }
  }

  private var bisectResultMessage: String {
    guard let culprit = model.bisectResult else { return "" }
    let subject = model.historyRows.first { $0.commit.oid == culprit }?.commit.subject
    return [culprit.shortened, subject].compactMap(\.self).joined(separator: " — ")
      + "\n\nThe bisect has ended and your original checkout is restored."
  }

  private func switchToWorktree(at path: URL) {
    let gitMetadataURL = path.appending(path: ".git")
    guard FileManager.default.fileExists(atPath: gitMetadataURL.path) else {
      switchWorktreeErrorMessage = "The worktree no longer exists at \(path.path)."
      return
    }

    let repositoryID = Repository(rootURL: path).id
    guard repositoryID != model.repository.id else { return }
    model.stopWatching()
    switchRepository(repositoryID)
  }
}

extension RepositoryModel {
  fileprivate var commonWorktreeName: String {
    worktrees.first(where: \.isMain)?.name ?? repository.name
  }
}
