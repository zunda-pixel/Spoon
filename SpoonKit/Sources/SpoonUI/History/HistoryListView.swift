import SpoonCore
import SwiftUI

@MainActor
struct HistoryListView: View {
  let model: RepositoryModel
  @Binding var selectedCommitID: String?
  @State private var rebaseSheetCommit: Commit?
  @State private var taggingCommit: Commit?

  init(model: RepositoryModel, selectedCommitID: Binding<String?>) {
    self.model = model
    self._selectedCommitID = selectedCommitID
  }

  var body: some View {
    Group {
      if model.historyRows.isEmpty {
        if model.isLoadingHistory {
          ProgressView()
        } else {
          ContentUnavailableView(
            "No Commits",
            systemImage: "clock",
            description: Text("This branch has no commits yet.")
          )
        }
      } else {
        List(selection: $selectedCommitID) {
          ForEach(model.historyRows) { row in
            CommitGraphRowView(row: row)
              .tag(row.id)
              .listRowSeparator(.hidden)
              .contextMenu {
                commitMenu(row.commit)
              }
              .onAppear {
                if row.id == model.historyRows.last?.id, model.hasMoreHistory {
                  Task { await model.loadMoreHistory() }
                }
              }
          }
          if model.hasMoreHistory {
            HStack {
              Spacer()
              ProgressView()
                .controlSize(.small)
              Spacer()
            }
            .listRowSeparator(.hidden)
          }
        }
        .listStyle(.plain)
      }
    }
    .task(id: model.repository.id) {
      await model.loadHistoryIfNeeded()
    }
    .sheet(item: $rebaseSheetCommit) { commit in
      RebaseSheet(model: model, fromCommit: commit)
    }
    .sheet(item: $taggingCommit) { commit in
      TagCommitSheet(model: model, commit: commit)
    }
  }

  @ViewBuilder
  private func commitMenu(_ commit: Commit) -> some View {
    Button("Checkout Commit (Detached)") {
      Task { await model.checkoutRevision(commit.oid) }
    }
    .disabled(model.isBusy || model.isSequencing)
    Button("Tag Commit…") {
      taggingCommit = commit
    }
    .disabled(model.isBusy)
    Divider()
    Button("Interactive Rebase from Here…") {
      rebaseSheetCommit = commit
    }
    .disabled(commit.isMerge || model.isBusy || model.isSequencing)
    Divider()
    Button("Cherry-Pick onto \(model.currentBranch?.name ?? "HEAD")") {
      Task { await model.cherryPick(commit.oid) }
    }
    .disabled(model.isBusy || model.isSequencing)
    Button("Revert Commit") {
      Task { await model.revert(commit.oid) }
    }
    .disabled(commit.isMerge || model.isBusy || model.isSequencing)
  }
}

@MainActor
struct TagCommitSheet: View {
  let model: RepositoryModel
  let commit: Commit
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var message = ""

  init(model: RepositoryModel, commit: Commit) {
    self.model = model
    self.commit = commit
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Tag \(commit.oid.shortened) — \(commit.subject)")
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.tail)
      Form {
        TextField("Tag name", text: $name, prompt: Text("v1.0.0"))
          .onSubmit(create)
        TextField("Message (optional; makes the tag annotated)", text: $message)
      }
      .textFieldStyle(.roundedBorder)
      .frame(width: 380)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Button("Create Tag", action: create)
          .keyboardShortcut(.defaultAction)
          .disabled(!isValid)
      }
    }
    .padding(20)
  }

  private var isValid: Bool {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    return !trimmed.isEmpty && !trimmed.contains(" ")
      && !model.tags.contains { $0.name == trimmed }
  }

  private func create() {
    guard isValid else { return }
    let tagName = name.trimmingCharacters(in: .whitespaces)
    let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
    dismiss()
    Task {
      await model.createTag(
        name: tagName,
        at: commit.oid,
        message: trimmedMessage.isEmpty ? nil : trimmedMessage
      )
    }
  }
}
