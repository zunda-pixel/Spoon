import AppKit
import SpoonCore
import SwiftUI

/// Detail column for a commit selected in History.
@MainActor
struct CommitDetailView: View {
  let model: RepositoryModel
  let oid: ObjectID

  @State private var detail: CommitDetail?
  @State private var errorMessage: String?
  @State private var lineSelection: DiffLineSelection?
  @State private var pendingRestore: FileRestoreRequest?

  init(model: RepositoryModel, oid: ObjectID) {
    self.model = model
    self.oid = oid
  }

  var body: some View {
    Group {
      // A detail for another commit stays in state until the selected one
      // loads; showing it would look like the selection didn't change.
      if let detail, detail.commit.oid == oid {
        VStack(spacing: 0) {
          header(detail)
          Divider()
          if let lineSelection {
            copyBar(lineSelection, diffs: detail.diffs)
            Divider()
          }
          DiffOptionsBar(model: model)
          Divider()
          FileDiffListView(
            diffs: detail.diffs,
            lineSelection: $lineSelection,
            fileActions: { restoreActions(for: $0, in: detail.commit) },
            highlightsWordChanges: model.diffHighlightsWordChanges
          )
        }
      } else if let errorMessage {
        ContentUnavailableView(
          "Could Not Load Commit",
          systemImage: "exclamationmark.triangle",
          description: Text(errorMessage)
        )
      } else {
        ProgressView()
      }
    }
    .confirmationDialog(
      pendingRestore?.title ?? "",
      isPresented: .init(
        get: { pendingRestore != nil },
        set: { if !$0 { pendingRestore = nil } }
      ),
      presenting: pendingRestore
    ) { request in
      Button(request.confirmTitle, role: .destructive) {
        Task { await model.restoreFile(path: request.path, from: request.revision) }
      }
    } message: { request in
      Text(
        "Uncommitted changes to \(request.path) are replaced. The index is not changed, so the result appears as an unstaged change."
      )
    }
    .task(id: DetailKey(oid: oid, options: model.diffOptions)) {
      errorMessage = nil
      lineSelection = nil
      do {
        let loaded = try await model.commitDetail(oid)
        // git calls run concurrently, so a superseded load can finish after
        // the current one; it must not overwrite it.
        guard !Task.isCancelled else { return }
        detail = loaded
      } catch {
        guard !Task.isCancelled else { return }
        detail = nil
        errorMessage = error.localizedDescription
      }
    }
  }

  private func restoreActions(for diff: FileDiff, in commit: Commit) -> [FileDiffAction] {
    let busy = model.isBusy || model.isSequencing
    var actions = [
      FileDiffAction(
        title: diff.kind == .deleted
          ? "Delete from Working Tree, as in This Commit…"
          : "Restore Version from This Commit…",
        isEnabled: !busy
      ) {
        pendingRestore = FileRestoreRequest(
          path: diff.path, revision: commit.oid, isDeletion: diff.kind == .deleted)
      }
    ]
    if let parent = commit.parents.first {
      actions.append(
        FileDiffAction(
          title: diff.kind == .added
            ? "Delete from Working Tree, as Before This Commit…"
            : "Restore Version from Before This Commit…",
          isEnabled: !busy
        ) {
          pendingRestore = FileRestoreRequest(
            path: diff.oldPath ?? diff.path, revision: parent, isDeletion: diff.kind == .added)
        }
      )
    }
    return actions
  }

  private func copyBar(_ lineSelection: DiffLineSelection, diffs: [FileDiff]) -> some View {
    LineSelectionBar(
      selection: lineSelection,
      onDeselect: { self.lineSelection = nil },
      actions: {
        Button("Copy Selected Lines") {
          copySelectedLines(lineSelection, diffs: diffs)
        }
      }
    )
  }

  /// Copies the selected lines' text without the +/- diff markers.
  private func copySelectedLines(_ selection: DiffLineSelection, diffs: [FileDiff]) {
    guard
      let diff = diffs.first(where: { $0.id == selection.fileID }),
      let hunk = diff.hunks.first(where: { $0.id == selection.hunkID })
    else { return }
    let text =
      selection.offsets.sorted()
      .filter { hunk.lines.indices.contains($0) }
      .map { hunk.lines[$0].text }
      .joined(separator: "\n")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private func header(_ detail: CommitDetail) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(detail.commit.subject)
        .font(.headline)
        .textSelection(.enabled)

      HStack(spacing: 8) {
        Text(detail.commit.oid.shortened)
          .font(.caption.monospaced())
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        Text(detail.commit.authorName)
        Text(detail.commit.committedAt, format: .dateTime)
        if detail.commit.isMerge {
          Label("Merge", systemImage: "arrow.triangle.merge")
        }
        if let signature = detail.signature {
          SignatureBadge(signature: signature)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      let body = messageBody(detail)
      if !body.isEmpty {
        Text(body)
          .font(.callout)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .lineLimit(12)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
  }

  private func messageBody(_ detail: CommitDetail) -> String {
    detail.fullMessage
      .dropFirst(detail.commit.subject.count)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// A confirmed-before-running `git restore --source` of one file.
private struct FileRestoreRequest: Hashable {
  let path: String
  let revision: ObjectID
  /// The file does not exist at `revision`, so restoring deletes it.
  let isDeletion: Bool

  var title: String {
    isDeletion
      ? "Delete \(path) from the working tree?"
      : "Restore \(path) from \(revision.shortened)?"
  }

  var confirmTitle: String { isDeletion ? "Delete File" : "Restore File" }
}

private struct DetailKey: Hashable {
  let oid: ObjectID
  let options: DiffOptions
}
