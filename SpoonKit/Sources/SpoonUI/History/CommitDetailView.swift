import AppKit
import SpoonCore
import SwiftUI

/// Detail column for a commit selected in History.
@MainActor
struct CommitDetailView: View {
  let model: RepositoryModel
  let oid: ObjectID
  /// Opens file history and blame from each file's menu; `nil` leaves
  /// them out, e.g. inside a sheet that can't present another.
  var navigation: RepositoryNavigationState?

  @State private var detail: CommitDetail?
  @State private var errorMessage: String?
  @State private var lineSelection: DiffLineSelection?
  @State private var pendingRestore: FileRestoreRequest?
  /// Tags around the commit, loaded after the detail since it is optional.
  @State private var description: (oid: ObjectID, value: CommitDescription)?
  /// Signed tags on the commit, with their verification.
  @State private var tagSignatures: (oid: ObjectID, values: [(tag: Tag, signature: CommitSignature)])?

  init(model: RepositoryModel, oid: ObjectID, navigation: RepositoryNavigationState? = nil) {
    self.model = model
    self.oid = oid
    self.navigation = navigation
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
            fileActions: { fileActions(for: $0) + restoreActions(for: $0, in: detail.commit) },
            highlightsWordChanges: model.diffHighlightsWordChanges,
            imageLoader: .revisions(
              model: model,
              old: detail.commit.parents.first?.rawValue,
              new: detail.commit.oid.rawValue
            )
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
        if let value = await model.describe(oid), !Task.isCancelled {
          description = (oid, value)
        }
        let signatures = await model.verifiedTags(at: oid)
        if !Task.isCancelled {
          tagSignatures = (oid, signatures)
        }
      } catch {
        guard !Task.isCancelled else { return }
        detail = nil
        errorMessage = error.localizedDescription
      }
    }
  }

  /// File history follows renames, so it starts from the path the file
  /// has in this commit. Blame reads the working-tree copy.
  private func fileActions(for diff: FileDiff) -> [FileDiffAction] {
    guard let navigation else { return [] }
    var actions = [
      FileDiffAction(title: "Show File History…") {
        navigation.present(.fileHistory(path: diff.path))
      }
    ]
    let fileURL = model.repository.rootURL.appending(path: diff.path)
    if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
      actions.append(
        FileDiffAction(title: "Blame…") {
          navigation.present(.blame(path: diff.path))
        }
      )
    }
    return actions
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
        if let description, description.oid == detail.commit.oid {
          TagPositionLabels(description: description.value)
        }
        if let tagSignatures, tagSignatures.oid == detail.commit.oid {
          ForEach(tagSignatures.values, id: \.tag.name) { entry in
            SignatureBadge(signature: entry.signature, subject: "Tag \(entry.tag.name)")
          }
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

/// "0.0.9 + 1" (the nearest earlier tag) and "In 0.0.10" (the first tag
/// that contains the commit), from `git describe`.
@MainActor
private struct TagPositionLabels: View {
  let description: CommitDescription

  var body: some View {
    if let tag = description.nearestTag {
      if description.commitsSinceTag == 0 {
        Label(tag, systemImage: "tag")
          .help("Tagged \(tag)")
      } else {
        Label("\(tag) + \(description.commitsSinceTag)", systemImage: "tag")
          .help(
            "\(description.commitsSinceTag) \(description.commitsSinceTag == 1 ? "commit" : "commits") after \(tag) (git describe)"
          )
      }
    }
    if let released = description.firstContainingTag,
      released != description.nearestTag || description.commitsSinceTag != 0
    {
      Label("In \(released)", systemImage: "shippingbox")
        .help("First included in \(released) (git describe --contains)")
    }
  }
}
