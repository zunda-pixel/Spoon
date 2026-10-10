import AppKit
import SpoonCore
import SwiftUI

/// `git grep` across the working tree or one branch or tag, with matches
/// grouped by file.
@MainActor
struct CodeSearchSheet: View {
  let model: RepositoryModel
  @Bindable var navigation: RepositoryNavigationState
  @Environment(\.dismiss) private var dismiss

  @State private var pattern = ""
  @State private var paths = ""
  /// `nil` searches the working tree.
  @State private var revision: String?
  @State private var matchesCase = false
  @State private var matchesWholeWord = false
  @State private var usesRegularExpression = false
  @State private var includesUntracked = false
  /// The query whose results are shown; set on Return and when an option
  /// changes, so typing alone doesn't run git for every keystroke.
  @State private var submittedQuery: CodeSearchQuery?
  @State private var loadState: AsyncLoadState<CodeSearchResult>?
  @State private var selection: Set<CodeSearchMatch.ID> = []
  @FocusState private var isPatternFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      results
    }
    .frame(minWidth: 820, minHeight: 560)
    .onAppear { isPatternFocused = true }
    .onChange(of: optionsKey) { submit() }
    .task(id: submittedQuery) {
      guard let submittedQuery else { return }
      loadState = .loading
      do {
        let result = try await model.searchCode(submittedQuery)
        guard !Task.isCancelled else { return }
        loadState = .loaded(result)
        selection = []
      } catch {
        guard !Task.isCancelled else { return }
        loadState = .failed(error.localizedDescription)
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("Search code", text: $pattern)
          .textFieldStyle(.roundedBorder)
          .focused($isPatternFocused)
          .onSubmit(submit)
          .accessibilityLabel("Search pattern")
        Button("Search", action: submit)
          .keyboardShortcut(.defaultAction)
          .disabled(pattern.isEmpty)
        Button("Done") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
      HStack(spacing: 12) {
        Toggle("Match Case", isOn: $matchesCase)
        Toggle("Whole Word", isOn: $matchesWholeWord)
        Toggle("Regular Expression", isOn: $usesRegularExpression)
          .help("POSIX extended regular expression, as git grep -E reads it")
        Divider().frame(height: 16)
        Picker("In", selection: $revision) {
          Text("Working Tree").tag(String?.none)
          Divider()
          ForEach(model.branches) { branch in
            Text(branch.name).tag(String?.some(branch.name))
          }
          if !model.tags.isEmpty {
            Divider()
            ForEach(model.tags) { tag in
              Text(tag.name).tag(String?.some(tag.name))
            }
          }
        }
        .layoutPriority(1)
        Toggle("Include Untracked", isOn: $includesUntracked)
          .disabled(revision != nil)
          .help("Also search files git doesn’t track yet")
        TextField("Files, e.g. *.swift Sources/", text: $paths)
          .textFieldStyle(.roundedBorder)
          .frame(minWidth: 160)
          .onSubmit(submit)
          .accessibilityLabel("Limit to files")
      }
      .toggleStyle(.checkbox)
      .controlSize(.small)
    }
    .padding(12)
  }

  @ViewBuilder
  private var results: some View {
    if let loadState, let submittedQuery {
      AsyncContentView(
        state: loadState,
        isEmpty: \.matches.isEmpty,
        content: { resultList($0, query: submittedQuery) },
        empty: {
          ContentUnavailableView.search(text: submittedQuery.pattern)
        },
        errorTitle: "Could Not Search"
      )
    } else {
      ContentUnavailableView(
        "Search Code",
        systemImage: "text.magnifyingglass",
        description: Text("Find text in every tracked file with git grep.")
      )
    }
  }

  private func resultList(_ result: CodeSearchResult, query: CodeSearchQuery) -> some View {
    let files = result.files
    return VStack(spacing: 0) {
      HStack {
        Text(summary(result, fileCount: files.count))
          .font(.callout)
          .foregroundStyle(.secondary)
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      Divider()
      List(selection: $selection) {
        ForEach(files, id: \.path) { file in
          Section {
            ForEach(file.matches) { match in
              CodeSearchRow(match: match, query: query)
            }
          } header: {
            HStack {
              Label(file.path, systemImage: "doc.text")
                .lineLimit(1)
                .truncationMode(.middle)
              Spacer()
              Text("\(file.matches.count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .contextMenu(forSelectionType: CodeSearchMatch.ID.self) { ids in
        if let match = firstMatch(of: ids, in: result) {
          matchMenu(match, isWorkingTree: query.revision == nil)
        }
      } primaryAction: { ids in
        guard query.revision == nil, let match = firstMatch(of: ids, in: result) else { return }
        NSWorkspace.shared.open(fileURL(match.path))
      }
    }
  }

  @ViewBuilder
  private func matchMenu(_ match: CodeSearchMatch, isWorkingTree: Bool) -> some View {
    if isWorkingTree {
      Button("Open") { NSWorkspace.shared.open(fileURL(match.path)) }
      Button("Reveal in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL(match.path)])
      }
      Divider()
      Button("Blame…") { navigation.present(.blame(path: match.path)) }
      Button("Show History of This Line…") {
        navigation.present(
          .lineHistory(path: match.path, lines: match.lineNumber...match.lineNumber))
      }
      .disabled(model.hasUncommittedChanges(at: match.path))
      .help(LineHistorySheet.uncommittedHelp)
    }
    Button("Show File History…") { navigation.present(.fileHistory(path: match.path)) }
    Divider()
    Button("Copy Line") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(match.text, forType: .string)
    }
    Button("Copy Path") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString("\(match.path):\(match.lineNumber)", forType: .string)
    }
  }

  private func summary(_ result: CodeSearchResult, fileCount: Int) -> String {
    let lines = result.matches.count == 1 ? "1 line" : "\(result.matches.count) lines"
    let files = fileCount == 1 ? "1 file" : "\(fileCount) files"
    return result.isTruncated
      ? "Showing the first \(lines) in \(files). Narrow the search to see the rest."
      : "\(lines) in \(files)"
  }

  private func firstMatch(of ids: Set<CodeSearchMatch.ID>, in result: CodeSearchResult)
    -> CodeSearchMatch?
  {
    result.matches.first { ids.contains($0.id) }
  }

  private func fileURL(_ path: String) -> URL {
    model.repository.rootURL.appending(path: path)
  }

  /// Every option but the pattern: changing one reruns the last search.
  private var optionsKey: [String] {
    [
      "\(matchesCase)", "\(matchesWholeWord)", "\(usesRegularExpression)",
      "\(includesUntracked)", revision ?? "",
    ]
  }

  private func submit() {
    guard !pattern.isEmpty else { return }
    submittedQuery = CodeSearchQuery(
      pattern: pattern,
      revision: revision,
      matchesCase: matchesCase,
      matchesWholeWord: matchesWholeWord,
      syntax: usesRegularExpression ? .regularExpression : .literal,
      includesUntracked: includesUntracked,
      paths: paths.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
    )
  }
}

@MainActor
private struct CodeSearchRow: View {
  let match: CodeSearchMatch
  let query: CodeSearchQuery

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text("\(match.lineNumber)")
        .foregroundStyle(.tertiary)
        .monospacedDigit()
        .frame(minWidth: 40, alignment: .trailing)
        .accessibilityLabel("Line \(match.lineNumber)")
      Text(highlighted)
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .font(.callout.monospaced())
    .help(match.text)
    .accessibilityElement(children: .combine)
  }

  /// The line without its indentation, each match tinted.
  private var highlighted: AttributedString {
    let text = String(match.text.drop(while: { $0 == " " || $0 == "\t" }))
    var attributed = AttributedString(text)
    for range in query.matchRanges(in: text) {
      guard let converted = Range(range, in: attributed) else { continue }
      attributed[converted].backgroundColor = .yellow.opacity(0.35)
      attributed[converted].inlinePresentationIntent = .stronglyEmphasized
    }
    return attributed
  }
}
