import SpoonCore
import SwiftUI

/// Search field above the history list. Submitting a query swaps the graph
/// for a flat list of matching commits.
@MainActor
struct HistorySearchBar: View {
  @Binding var text: String
  @Binding var field: HistorySearch.Field
  let submit: () -> Void
  let clear: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Picker("Search in", selection: $field) {
        Text("Message").tag(HistorySearch.Field.message)
        Text("Author").tag(HistorySearch.Field.author)
        Text("Code").tag(HistorySearch.Field.code)
      }
      .labelsHidden()
      .fixedSize()
      .help("Search commit messages, authors, or commits that add or remove the text")
      TextField("Search history", text: $text, prompt: Text(prompt))
        .textFieldStyle(.roundedBorder)
        .onSubmit(submit)
      if !text.isEmpty {
        Button("Clear Search", systemImage: "xmark.circle.fill", action: clear)
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .foregroundStyle(.secondary)
          .help("Clear the search and show the full history")
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .overlay(alignment: .bottom) {
      Divider()
    }
    .onChange(of: field) {
      if !text.trimmingCharacters(in: .whitespaces).isEmpty {
        submit()
      }
    }
  }

  private var prompt: String {
    switch field {
    case .message: "Search commit messages"
    case .author: "Search authors"
    case .code: "Search added or removed code"
    }
  }
}

/// Commits matching a history search, newest first, loaded page by page.
@MainActor
struct HistorySearchResultsView: View {
  let model: RepositoryModel
  let search: HistorySearch
  @Bindable var navigation: RepositoryNavigationState
  @State private var loadState: AsyncLoadState<[Commit]> = .loading
  @State private var nextSkip: Int?
  @State private var isLoadingMore = false

  var body: some View {
    AsyncContentView(
      state: loadState,
      isEmpty: \.isEmpty,
      content: { resultList($0) },
      empty: {
        ContentUnavailableView.search(text: search.text)
      },
      errorTitle: "Could Not Search History"
    )
    .task(id: search) {
      await loadFirstPage()
    }
  }

  private func resultList(_ commits: [Commit]) -> some View {
    List(selection: $navigation.selectedCommitID) {
      ForEach(commits) { commit in
        HistorySearchResultRow(commit: commit)
          .tag(commit.id)
          .onAppear {
            if commit.id == commits.last?.id, nextSkip != nil {
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
    loadState = .loading
    nextSkip = nil
    do {
      let page = try await model.searchHistory(search)
      loadState = .loaded(page.commits)
      nextSkip = page.hasMore ? 200 : nil
    } catch {
      loadState = .failed(error.localizedDescription)
    }
  }

  private func loadMore() async {
    guard let skip = nextSkip, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let page = try await model.searchHistory(search, skip: skip)
      guard case .loaded(let commits) = loadState else { return }
      loadState = .loaded(commits + page.commits)
      nextSkip = page.hasMore ? skip + 200 : nil
    } catch {
      loadState = .failed(error.localizedDescription)
      nextSkip = nil
    }
  }
}

private struct HistorySearchResultRow: View {
  let commit: Commit

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(commit.subject)
        .lineLimit(1)
      HStack(spacing: 6) {
        Text(commit.oid.shortened)
          .font(.caption.monospaced())
        Text(commit.authorName)
        Text(commit.committedAt, format: .relative(presentation: .named))
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }
}
