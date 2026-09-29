import SpoonCore
import SwiftUI

/// Line-by-line authorship of one file, with each run of lines from the
/// same commit labelled once.
@MainActor
struct BlameSheet: View {
  let model: RepositoryModel
  let path: String
  @Bindable var navigation: RepositoryNavigationState
  @Environment(\.dismiss) private var dismiss
  @State private var loadState: AsyncLoadState<[BlameLine]> = .loading

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Blame — \(path)")
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
        content: { blameList($0) },
        empty: {
          ContentUnavailableView(
            "Empty File",
            systemImage: "doc",
            description: Text("There are no lines to blame.")
          )
        },
        errorTitle: "Could Not Blame File"
      )
    }
    .frame(minWidth: 820, minHeight: 520)
    .task(id: path) {
      do {
        loadState = .loaded(try await model.blame(path: path))
      } catch {
        loadState = .failed(error.localizedDescription)
      }
    }
  }

  private func blameList(_ lines: [BlameLine]) -> some View {
    // Vertical only: long lines wrap, so every row, and each commit's
    // separator, spans the full width of the sheet.
    ScrollView(.vertical) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
          let startsRun = index == 0 || lines[index - 1].commit.oid != line.commit.oid
          BlameRow(line: line, showsCommit: startsRun) {
            showInHistory(line.commit)
          }
        }
      }
      .padding(.vertical, 4)
    }
  }

  private func showInHistory(_ commit: BlameCommit) {
    guard !commit.isUncommitted else { return }
    navigation.select(.history)
    navigation.selectedCommitID = commit.oid.rawValue
    dismiss()
  }
}

@MainActor
private struct BlameRow: View {
  let line: BlameLine
  let showsCommit: Bool
  let showCommit: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      commitLabel
        .frame(width: 280, alignment: .leading)
      Text("\(line.lineNumber)")
        .foregroundStyle(.tertiary)
        .frame(minWidth: 36, alignment: .trailing)
        .accessibilityLabel("Line \(line.lineNumber)")
      Text(line.text.isEmpty ? " " : line.text)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
    .font(.callout.monospaced())
    .padding(.horizontal, 12)
    .padding(.top, showsCommit ? 6 : 0)
    .overlay(alignment: .top) {
      if showsCommit {
        Divider()
      }
    }
  }

  @ViewBuilder
  private var commitLabel: some View {
    if showsCommit {
      let commit = line.commit
      if commit.isUncommitted {
        Text("Not committed yet")
          .foregroundStyle(.secondary)
      } else {
        Button(action: showCommit) {
          HStack(spacing: 6) {
            Text(commit.oid.shortened)
            Text(commit.authorName)
              .lineLimit(1)
            Text(commit.authoredAt, format: .dateTime.year().month().day())
          }
          .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(commit.summary)
        .accessibilityLabel("\(commit.oid.shortened), \(commit.authorName): \(commit.summary)")
        .accessibilityHint("Shows this commit in History")
      }
    } else {
      Color.clear.frame(height: 1)
    }
  }
}
