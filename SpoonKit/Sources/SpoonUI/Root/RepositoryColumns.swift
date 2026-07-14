import SpoonCore
import SwiftUI

@MainActor
struct RepositoryContentColumn: View {
  let model: RepositoryModel
  @Bindable var navigation: RepositoryNavigationState

  var body: some View {
    switch navigation.sidebarSelection {
    case .changes, nil:
      ChangesView(model: model, selection: $navigation.fileSelections, navigation: navigation)
    case .history:
      HistoryListView(model: model, reference: nil, navigation: navigation)
    case .branch(let name):
      HistoryListView(model: model, reference: name, navigation: navigation)
    case .remoteBranch(_, let branch):
      HistoryListView(model: model, reference: branch, navigation: navigation)
    case .reflog:
      ReflogView(model: model, navigation: navigation)
    case .pullRequests:
      PRListView(model: model, selectedPRNumber: $navigation.selectedPRNumber)
    case .remote(let name):
      RemoteDetailView(model: model, remoteName: name)
    case .stash(let index):
      StashDetailView(model: model, stashIndex: index)
    }
  }
}

@MainActor
struct RepositoryDetailColumn: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState

  var body: some View {
    switch navigation.sidebarSelection {
    case .changes, nil:
      changeDetail
    case .history, .branch, .remoteBranch:
      if let selectedCommitID = navigation.selectedCommitID,
        let oid = ObjectID(rawValue: selectedCommitID)
      {
        CommitDetailView(model: model, oid: oid)
      } else {
        SelectionPlaceholder()
      }
    case .reflog:
      if let oid = navigation.selectedReflogOID {
        CommitDetailView(model: model, oid: oid)
      } else {
        SelectionPlaceholder()
      }
    case .pullRequests:
      if let number = navigation.selectedPRNumber,
        let pullRequest = model.openPullRequests.first(where: { $0.number == number })
      {
        PRDetailView(pullRequest: pullRequest)
      } else {
        SelectionPlaceholder()
      }
    case .remote, .stash:
      SelectionPlaceholder()
    }
  }

  @ViewBuilder
  private var changeDetail: some View {
    if navigation.fileSelections.count == 1, let single = navigation.fileSelections.first {
      DiffDetailView(model: model, selection: single)
    } else if navigation.fileSelections.count > 1 {
      MultiSelectionActionsView(model: model, selections: navigation.fileSelections)
    } else {
      SelectionPlaceholder()
    }
  }
}

@MainActor
struct MultiSelectionActionsView: View {
  let model: RepositoryModel
  let selections: Set<RepositoryModel.FileSelection>

  var body: some View {
    let stageable = selections.filter { $0.area != .staged }
    let staged = selections.filter { $0.area == .staged }

    VStack(spacing: 14) {
      Image(systemName: "doc.on.doc")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text("\(selections.count) files selected")
        .font(.title3)
      HStack {
        if !stageable.isEmpty {
          Button("Stage \(stageable.count) File(s)") {
            Task { await model.stage(paths: stageable.map(\.path)) }
          }
        }
        if !staged.isEmpty {
          Button("Unstage \(staged.count) File(s)") {
            Task { await model.unstage(paths: staged.map(\.path)) }
          }
        }
      }
      .disabled(model.isBusy)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
