import SpoonCore
import SwiftUI

@MainActor
struct RepositoryWindowRoot: View {
  let repositoryID: Repository.ID
  let switchRepository: (Repository.ID) -> Void

  @Environment(AppModel.self) private var appModel
  @State private var cachedModels: [Repository.ID: RepositoryModel] = [:]
  @State private var cacheRecency: [Repository.ID] = []
  @State private var activeModel: RepositoryModel?
  @State private var loadErrorMessage: String?

  var body: some View {
    Group {
      if let model = cachedModels[repositoryID] {
        RepositorySplitView(model: model, switchRepository: switchRepository)
          .id(repositoryID)
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

  private func touchCacheEntry(_ id: Repository.ID) {
    cacheRecency.removeAll { $0 == id }
    cacheRecency.append(id)
  }

  private func insertIntoCache(_ model: RepositoryModel) {
    let id = model.repository.id
    cachedModels[id] = model
    touchCacheEntry(id)

    while cachedModels.count > 6, let evictedID = cacheRecency.first {
      cacheRecency.removeFirst()
      guard let evictedModel = cachedModels.removeValue(forKey: evictedID) else { continue }
      evictedModel.stopWatching()
    }
  }
}

@MainActor
struct RepositorySplitView: View {
  let model: RepositoryModel
  let switchRepository: (Repository.ID) -> Void
  @State private var navigation = RepositoryNavigationState()

  var body: some View {
    NavigationSplitView {
      RepoSidebarView(
        model: model,
        navigation: navigation,
        switchRepository: switchRepository
      )
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    } content: {
      RepositoryContentColumn(model: model, navigation: navigation)
        .navigationSplitViewColumnWidth(min: 300, ideal: 380)
    } detail: {
      RepositoryDetailColumn(model: model, navigation: navigation)
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if let state = model.sequencerState {
        SequencerBannerView(model: model, state: state)
      }
    }
    .navigationTitle(model.commonWorktreeName)
    .navigationSubtitle(model.repository.rootURL.path(percentEncoded: false))
    .navigationDocument(model.repository.rootURL)
    .toolbar {
      RepositoryToolbar(model: model, navigation: navigation)
    }
    .repositorySheets(model: model, navigation: navigation)
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
    .focusedSceneValue(\.repositoryModel, model)
    .focusedSceneValue(\.repositoryNavigationState, navigation)
  }

  private var sequencerName: String {
    switch model.sequencerState?.kind {
    case .rebase: "Rebase"
    case .cherryPick: "Cherry-Pick"
    case .revert: "Revert"
    case .merge: "Merge"
    case nil: "Operation"
    }
  }
}

private extension RepositoryModel {
  var commonWorktreeName: String {
    worktrees.first(where: \.isMain)?.name ?? repository.name
  }
}
