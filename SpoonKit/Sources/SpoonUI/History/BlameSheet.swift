import AppKit
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
  /// Lines picked by clicking their numbers; Shift-click extends from `anchor`.
  @State private var selectedLines: ClosedRange<Int>?
  @State private var anchor: Int?
  @State private var ignoreSettings = BlameIgnoreSettings()
  /// Honor the repository's list of commits for blame to look past.
  @State private var skipsListedCommits = true
  /// Commits picked here to look past, for this sheet only.
  @State private var ignoredCommits: [BlameCommit] = []

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Blame — \(path)")
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer()
        if let selectedLines {
          Button("Show History of \(LineHistorySheet.describe(selectedLines))") {
            navigation.present(.lineHistory(path: path, lines: selectedLines))
          }
          .disabled(model.hasUncommittedChanges(at: path))
          .help(LineHistorySheet.uncommittedHelp)
        } else {
          Text("Click line numbers to pick lines")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Button("Done") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
      .padding(12)
      if ignoreSettings.hasList || !ignoredCommits.isEmpty {
        ignoreBar
      }
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
      ignoreSettings = await model.blameIgnoreSettings()
      await load()
    }
    .onChange(of: blameOptions) {
      Task { await load() }
    }
  }

  private var blameOptions: BlameOptions {
    ignoreSettings.options(
      skippingListedCommits: skipsListedCommits, ignoring: ignoredCommits.map(\.oid))
  }

  private func load() async {
    do {
      loadState = .loaded(try await model.blame(path: path, options: blameOptions))
    } catch {
      loadState = .failed(error.localizedDescription)
    }
  }

  private var ignoreBar: some View {
    HStack(spacing: 12) {
      if ignoreSettings.hasList {
        Toggle(
          "Skip commits listed in \(ignoreSettings.listFileForAdding)", isOn: $skipsListedCommits
        )
        .toggleStyle(.checkbox)
        .help("Attribute lines to the commit before a listed one, such as a reformat")
      }
      if !ignoredCommits.isEmpty {
        Text(
          ignoredCommits.count == 1
            ? "Also skipping \(ignoredCommits[0].oid.shortened)"
            : "Also skipping \(ignoredCommits.count) commits"
        )
        .foregroundStyle(.secondary)
        .help(ignoredCommits.map { "\($0.oid.shortened) \($0.summary)" }.joined(separator: "\n"))
        Button("Stop Skipping") { ignoredCommits = [] }
      }
      Spacer()
    }
    .controlSize(.small)
    .padding(.horizontal, 12)
    .padding(.bottom, 8)
  }

  private func ignore(_ commit: BlameCommit) {
    guard !ignoredCommits.contains(where: { $0.oid == commit.oid }) else { return }
    ignoredCommits.append(commit)
  }

  private func addToIgnoreList(_ commit: BlameCommit) {
    Task {
      if await model.addToBlameIgnoreList(commit, settings: ignoreSettings) {
        ignoreSettings = await model.blameIgnoreSettings()
        skipsListedCommits = true
        await load()
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
          BlameRow(
            line: line,
            showsCommit: startsRun,
            isSelected: selectedLines?.contains(line.lineNumber) == true,
            showCommit: { showInHistory(line.commit) },
            selectLine: { select(line.lineNumber) },
            ignoreCommit: { ignore(line.commit) },
            addToIgnoreList: { addToIgnoreList(line.commit) },
            ignoreListFile: ignoreSettings.listFileForAdding
          )
        }
      }
      .padding(.vertical, 4)
    }
  }

  private func select(_ line: Int) {
    if NSEvent.modifierFlags.contains(.shift), let anchor {
      selectedLines = min(anchor, line)...max(anchor, line)
    } else if selectedLines == line...line {
      selectedLines = nil
      anchor = nil
    } else {
      selectedLines = line...line
      anchor = line
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
  let isSelected: Bool
  let showCommit: () -> Void
  let selectLine: () -> Void
  let ignoreCommit: () -> Void
  let addToIgnoreList: () -> Void
  let ignoreListFile: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      commitLabel
        .frame(width: 280, alignment: .leading)
      Button(action: selectLine) {
        Text("\(line.lineNumber)")
          .foregroundStyle(isSelected ? .primary : .tertiary)
          .frame(minWidth: 36, alignment: .trailing)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Line \(line.lineNumber)")
      .accessibilityHint("Selects this line; Shift-click selects a range")
      .accessibilityAddTraits(isSelected ? .isSelected : [])
      Text(line.text.isEmpty ? " " : line.text)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
    .font(.callout.monospaced())
    .padding(.horizontal, 12)
    .padding(.top, showsCommit ? 6 : 0)
    .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
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
        .accessibilityHint("Shows this commit in History; more actions in its context menu")
        .contextMenu {
          Button("Show in History", action: showCommit)
          Divider()
          Button("Skip This Commit", action: ignoreCommit)
            .help("Attribute its lines to the commit before it, for this view")
          Button("Add to \(ignoreListFile)", action: addToIgnoreList)
            .help("List it so blame skips it for everyone; commit the file to share it")
        }
      }
    } else {
      Color.clear.frame(height: 1)
    }
  }
}
