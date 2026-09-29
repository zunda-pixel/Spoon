import SpoonCore
import SwiftUI

/// The commits that changed a range of lines, newest first, each with the
/// diff of just those lines (`git log -L`).
@MainActor
struct LineHistorySheet: View {
  let model: RepositoryModel
  let path: String
  let lines: ClosedRange<Int>
  @Bindable var navigation: RepositoryNavigationState
  @Environment(\.dismiss) private var dismiss
  @State private var loadState: AsyncLoadState<[LineHistoryEntry]> = .loading
  @State private var selectedID: LineHistoryEntry.ID?

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("History of \(Self.describe(lines)) — \(path)")
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
      .padding(12)
      Divider()
      AsyncContentView(
        state: loadState,
        isEmpty: \.isEmpty,
        content: { content($0) },
        empty: {
          ContentUnavailableView(
            "No History",
            systemImage: "clock",
            description: Text("No commit changed these lines.")
          )
        },
        errorTitle: "Could Not Load Line History"
      )
    }
    .frame(minWidth: 900, minHeight: 560)
    .task(id: "\(path)|\(lines)") {
      do {
        let entries = try await model.lineHistory(path: path, lines: lines)
        loadState = .loaded(entries)
        selectedID = entries.first?.id
      } catch {
        loadState = .failed(error.localizedDescription)
      }
    }
  }

  /// Line history reads the file as HEAD has it, so working-tree line
  /// numbers only match when the file has no uncommitted changes.
  static let uncommittedHelp =
    "Show the commits that changed these lines. The file must have no uncommitted changes."

  /// "Line 12" or "Lines 12–20".
  static func describe(_ lines: ClosedRange<Int>) -> String {
    lines.count == 1 ? "Line \(lines.lowerBound)" : "Lines \(lines.lowerBound)–\(lines.upperBound)"
  }

  private func content(_ entries: [LineHistoryEntry]) -> some View {
    HSplitView {
      List(entries, selection: $selectedID) { entry in
        LineHistoryRow(commit: entry.commit)
          .tag(entry.id)
          .contextMenu {
            Button("Show in History") { showInHistory(entry.commit) }
          }
      }
      .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
      Group {
        if let entry = entries.first(where: { $0.id == selectedID }) {
          FileDiffListView(
            diffs: entry.diffs,
            highlightsWordChanges: model.diffHighlightsWordChanges
          )
        } else {
          ContentUnavailableView(
            "No Commit Selected", systemImage: "clock",
            description: Text("Select a commit to see how it changed these lines."))
        }
      }
      .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func showInHistory(_ commit: Commit) {
    navigation.select(.history)
    navigation.selectedCommitID = commit.id
    dismiss()
  }
}

@MainActor
private struct LineHistoryRow: View {
  let commit: Commit

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(commit.subject)
        .lineLimit(2)
      HStack(spacing: 6) {
        Text(commit.oid.shortened)
          .font(.caption.monospaced())
        Text(commit.authorName)
          .lineLimit(1)
        Text(commit.authoredAt, format: .relative(presentation: .named))
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}
