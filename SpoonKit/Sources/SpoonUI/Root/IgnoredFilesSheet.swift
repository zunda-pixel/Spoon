import AppKit
import SpoonCore
import SwiftUI

/// The untracked paths git ignores, each with the rule responsible, and a
/// field to ask why any path is, or isn't, ignored (`git check-ignore`).
@MainActor
struct IgnoredFilesSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var loadState: AsyncLoadState<(paths: [RepositoryModel.IgnoredPath], isTruncated: Bool)> =
    .loading
  @State private var query = ""
  @State private var checked: (path: String, status: IgnoreStatus)?
  @State private var checkError: String?
  /// Ignored paths to delete once confirmed; empty means every one.
  @State private var pendingDelete: [String]?

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Ignored Files")
          .font(.headline)
        Spacer()
        if case .loaded(let result) = loadState, !result.paths.isEmpty {
          Button("Delete All Ignored Files…", role: .destructive) { pendingDelete = [] }
            .disabled(model.isBusy)
            .help("Delete every ignored file and folder, such as build output (git clean -X)")
        }
        Button("Done") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
      .padding(12)
      checkRow
      Divider()
      AsyncContentView(
        state: loadState,
        isEmpty: { $0.paths.isEmpty },
        content: { list($0.paths, isTruncated: $0.isTruncated) },
        empty: {
          ContentUnavailableView(
            "Nothing Ignored",
            systemImage: "eye",
            description: Text("No untracked file here matches an ignore rule.")
          )
        },
        errorTitle: "Could Not List Ignored Files"
      )
    }
    .frame(minWidth: 720, minHeight: 520)
    .task { await load() }
    .confirmationDialog(
      deleteTitle,
      isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    ) {
      Button("Delete", role: .destructive) {
        guard let paths = pendingDelete else { return }
        Task {
          await model.deleteIgnored(paths)
          await load()
        }
      }
    } message: {
      Text(
        "They are deleted from disk, not moved to the Trash, and can only be recreated, e.g. by building again. Tracked files and untracked files that aren’t ignored stay."
      )
    }
  }

  private func load() async {
    do {
      loadState = .loaded(try await model.ignoredPaths())
    } catch {
      loadState = .failed(error.localizedDescription)
    }
  }

  private var deleteTitle: String {
    guard let pendingDelete else { return "" }
    switch pendingDelete.count {
    case 0: return "Delete every ignored file and folder?"
    case 1: return "Delete “\(pendingDelete[0])”?"
    default: return "Delete \(pendingDelete.count) ignored paths?"
    }
  }

  // MARK: - Checking one path

  private var checkRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        TextField("Why is this path ignored?", text: $query, prompt: Text("e.g. build/app.log"))
          .textFieldStyle(.roundedBorder)
          .onSubmit(check)
        Button("Check", action: check)
          .disabled(trimmedQuery.isEmpty)
      }
      if let checked {
        checkResult(checked.path, checked.status)
      } else if let checkError {
        Label(checkError, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.secondary)
      }
    }
    .font(.callout)
    .padding(.horizontal, 12)
    .padding(.bottom, 10)
  }

  @ViewBuilder
  private func checkResult(_ path: String, _ status: IgnoreStatus) -> some View {
    HStack(spacing: 6) {
      switch status {
      case .tracked:
        Label("“\(path)” is tracked, so ignore rules don’t apply to it.", systemImage: "doc.badge.clock")
      case .notIgnored:
        Label("“\(path)” is not ignored: no rule matches it.", systemImage: "eye")
      case .ignored(let rule):
        Label("“\(path)” is ignored by", systemImage: "eye.slash")
        RuleLabel(rule: rule)
        openButton(rule)
      case .reincluded(let rule):
        Label("“\(path)” is not ignored: it is re-included by", systemImage: "eye")
        RuleLabel(rule: rule)
        openButton(rule)
      }
    }
    .lineLimit(1)
    .truncationMode(.middle)
  }

  private var trimmedQuery: String {
    query.trimmingCharacters(in: CharacterSet(charactersIn: " /").union(.newlines))
  }

  private func check() {
    let path = trimmedQuery
    guard !path.isEmpty else { return }
    Task {
      do {
        checked = (path, try await model.ignoreStatus(of: path))
        checkError = nil
      } catch {
        checked = nil
        checkError = error.localizedDescription
      }
    }
  }

  // MARK: - The list

  private func list(_ paths: [RepositoryModel.IgnoredPath], isTruncated: Bool) -> some View {
    VStack(spacing: 0) {
      HStack {
        Text(
          isTruncated
            ? "Showing the first \(paths.count) ignored paths"
            : paths.count == 1 ? "1 ignored path" : "\(paths.count) ignored paths"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      List(paths) { entry in
        HStack(spacing: 8) {
          Label(
            entry.path,
            systemImage: entry.path.hasSuffix("/") ? "folder" : "doc"
          )
          .lineLimit(1)
          .truncationMode(.middle)
          Spacer(minLength: 12)
          if let rule = entry.rule {
            RuleLabel(rule: rule)
          }
        }
        .contextMenu {
          Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([url(entry.path)])
          }
          if let rule = entry.rule {
            Button("Open \(rule.source)") { open(rule) }
          }
          Divider()
          Button("Delete…", role: .destructive) { pendingDelete = [entry.path] }
            .disabled(model.isBusy)
          Divider()
          Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.path, forType: .string)
          }
        }
      }
    }
  }

  // MARK: - Helpers

  private func openButton(_ rule: IgnoreRule) -> some View {
    Button("Open") { open(rule) }
      .controlSize(.small)
      .help("Open \(rule.source)")
  }

  private func url(_ path: String) -> URL {
    model.repository.rootURL.appending(path: path)
  }

  /// Rule files are repository-relative, except `core.excludesFile`.
  private func open(_ rule: IgnoreRule) {
    let expanded = (rule.source as NSString).expandingTildeInPath
    let file =
      expanded.hasPrefix("/") ? URL(filePath: expanded) : url(rule.source)
    NSWorkspace.shared.open(file)
  }
}

/// `.gitignore:2  *.log`
@MainActor
private struct RuleLabel: View {
  let rule: IgnoreRule

  var body: some View {
    HStack(spacing: 6) {
      Text("\(rule.source):\(rule.line)")
        .foregroundStyle(.secondary)
      Text(rule.pattern)
        .padding(.horizontal, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
    .font(.callout.monospaced())
    .lineLimit(1)
    .truncationMode(.head)
    .help("Line \(rule.line) of \(rule.source): \(rule.pattern)")
  }
}
