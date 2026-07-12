import SpoonCore
import SwiftUI

@MainActor
struct HistoryListView: View {
  let model: RepositoryModel
  @Binding var selectedCommitID: String?

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
  }
}
