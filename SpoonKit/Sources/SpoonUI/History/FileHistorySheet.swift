import SpoonCore
import SwiftUI

@MainActor
struct FileHistorySheet: View {
  let model: RepositoryModel
  let path: String
  @Environment(\.dismiss) private var dismiss
  @State private var loadState: AsyncLoadState<[Commit]> = .loading
  @State private var selectedCommitID: String?
  @State private var nextQuery: LogQuery?
  @State private var isLoadingMore = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      NavigationSplitView {
        AsyncContentView(
          state: loadState,
          isEmpty: \.isEmpty,
          content: { historyList($0) },
          empty: {
            ContentUnavailableView(
              "No File History",
              systemImage: "clock",
              description: Text("No commits include this path.")
            )
          },
          errorTitle: "Could Not Load File History"
        )
        .navigationSplitViewColumnWidth(min: 280, ideal: 340)
      } detail: {
        if let selectedCommitID, let oid = ObjectID(rawValue: selectedCommitID) {
          CommitDetailView(model: model, oid: oid)
        } else {
          SelectionPlaceholder(
            title: "No Commit Selected",
            systemImage: "clock",
            description: "Select a commit to inspect its changes."
          )
        }
      }
    }
    .frame(minWidth: 760, minHeight: 480)
    .task(id: path) {
      await loadFirstPage()
    }
  }

  private var header: some View {
    HStack {
      Text("History — \(path)")
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
      Button("Done") {
        dismiss()
      }
      .keyboardShortcut(.cancelAction)
    }
    .padding(12)
  }

  private func historyList(_ commits: [Commit]) -> some View {
    List(selection: $selectedCommitID) {
      ForEach(commits) { commit in
        FileHistoryRow(commit: commit)
          .tag(commit.id)
          .onAppear {
            if commit.id == commits.last?.id, nextQuery != nil {
              Task { await loadMore() }
            }
          }
      }
      if isLoadingMore {
        ProgressView()
          .controlSize(.small)
          .frame(maxWidth: .infinity)
      }
    }
    .listStyle(.plain)
  }

  private func loadFirstPage() async {
    let query = LogQuery(path: path, maxCount: 200)
    do {
      let page = try await model.fileHistory(query)
      loadState = .loaded(page.commits)
      selectedCommitID = page.commits.first?.id
      nextQuery = page.hasMore ? query.next() : nil
    } catch {
      loadState = .failed(error.localizedDescription)
    }
  }

  private func loadMore() async {
    guard let query = nextQuery, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let page = try await model.fileHistory(query)
      guard case .loaded(let commits) = loadState else { return }
      loadState = .loaded(commits + page.commits)
      nextQuery = page.hasMore ? query.next() : nil
    } catch {
      loadState = .failed(error.localizedDescription)
      nextQuery = nil
    }
  }
}

private struct FileHistoryRow: View {
  let commit: Commit

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(commit.subject)
        .lineLimit(1)
      HStack {
        Text(commit.oid.shortened)
          .font(.caption.monospaced())
        Text(commit.committedAt, format: .relative(presentation: .named))
          .font(.caption)
      }
      .foregroundStyle(.secondary)
    }
  }
}
