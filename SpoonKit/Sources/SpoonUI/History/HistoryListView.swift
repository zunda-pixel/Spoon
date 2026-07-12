import SpoonCore
import SwiftUI

@MainActor
struct HistoryListView: View {
  let model: RepositoryModel
  @Binding var selectedCommitID: String?
  @State private var rebaseSheetCommit: Commit?

  init(model: RepositoryModel, selectedCommitID: Binding<String?>) {
    self.model = model
    self._selectedCommitID = selectedCommitID
  }

  var body: some View {
    Group {
      if model.historyRows.isEmpty {
        if model.isLoadingHistory {
          ProgressView()
        } else {
          ContentUnavailableView(
            "No Commits",
            systemImage: "clock",
            description: Text("This branch has no commits yet.")
          )
        }
      } else {
        List(selection: $selectedCommitID) {
          ForEach(model.historyRows) { row in
            CommitGraphRowView(row: row)
              .tag(row.id)
              .listRowSeparator(.hidden)
              .contextMenu {
                commitMenu(row.commit)
              }
              .onAppear {
                if row.id == model.historyRows.last?.id, model.hasMoreHistory {
                  Task { await model.loadMoreHistory() }
                }
              }
          }
          if model.hasMoreHistory {
            HStack {
              Spacer()
              ProgressView()
                .controlSize(.small)
              Spacer()
            }
            .listRowSeparator(.hidden)
          }
        }
        .listStyle(.plain)
      }
    }
    .task(id: model.repository.id) {
      await model.loadHistoryIfNeeded()
    }
    .sheet(item: $rebaseSheetCommit) { commit in
      RebaseSheet(model: model, fromCommit: commit)
    }
  }

  @ViewBuilder
  private func commitMenu(_ commit: Commit) -> some View {
    Button("Interactive Rebase from Here…") {
      rebaseSheetCommit = commit
    }
    .disabled(commit.isMerge || model.isBusy || model.isSequencing)
    Divider()
    Button("Cherry-Pick onto \(model.currentBranch?.name ?? "HEAD")") {
      Task { await model.cherryPick(commit.oid) }
    }
    .disabled(model.isBusy || model.isSequencing)
    Button("Revert Commit") {
      Task { await model.revert(commit.oid) }
    }
    .disabled(commit.isMerge || model.isBusy || model.isSequencing)
  }
}
