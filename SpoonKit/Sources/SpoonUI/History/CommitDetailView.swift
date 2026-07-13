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

  init(model: RepositoryModel, oid: ObjectID) {
    self.model = model
    self.oid = oid
  }

  var body: some View {
    Group {
      if let detail {
        VStack(spacing: 0) {
          header(detail)
          Divider()
          if let lineSelection {
            copyBar(lineSelection, diffs: detail.diffs)
            Divider()
          }
          FileDiffListView(diffs: detail.diffs, lineSelection: $lineSelection)
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
    .task(id: oid) {
      do {
        errorMessage = nil
        lineSelection = nil
        detail = try await model.commitDetail(oid)
      } catch {
        detail = nil
        errorMessage = error.localizedDescription
      }
    }
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
