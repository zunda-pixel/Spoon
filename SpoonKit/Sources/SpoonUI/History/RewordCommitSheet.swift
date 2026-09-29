import SpoonCore
import SwiftUI

/// Edits one commit's message with `git history reword`.
@MainActor
struct RewordCommitSheet: View {
  let model: RepositoryModel
  let commit: Commit
  @Environment(\.dismiss) private var dismiss
  @State private var message = ""
  @State private var originalMessage: String?
  @State private var loadErrorMessage: String?

  var body: some View {
    SheetFormLayout(
      title: "Edit Message of \(commit.oid.shortened)",
      subtitle: "Later commits are rewritten; files and the index are not touched."
    ) {
      Group {
        if let loadErrorMessage {
          Label(loadErrorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
        } else if originalMessage == nil {
          ProgressView()
            .frame(maxWidth: .infinity, minHeight: 160)
        } else {
          TextEditor(text: $message)
            .font(.body.monospaced())
            .frame(minHeight: 160)
            .accessibilityLabel("Commit message")
        }
      }
      .frame(width: 460, alignment: .leading)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Save Message", action: save)
        .keyboardShortcut(.defaultAction)
        .disabled(!canSave)
    }
    .task {
      do {
        let detail = try await model.commitDetail(commit.oid)
        originalMessage = detail.fullMessage
        message = detail.fullMessage
      } catch {
        loadErrorMessage = error.localizedDescription
      }
    }
  }

  private var trimmedMessage: String {
    message.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canSave: Bool {
    guard let originalMessage, !model.isBusy, !model.isSequencing else { return false }
    return !trimmedMessage.isEmpty
      && trimmedMessage != originalMessage.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func save() {
    let newMessage = trimmedMessage + "\n"
    let oid = commit.oid
    dismiss()
    Task { await model.rewordCommit(oid, message: newMessage) }
  }
}
