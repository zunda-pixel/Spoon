import SpoonCore
import SwiftUI

@MainActor
struct HistoryListView: View {
  let model: RepositoryModel
  let reference: String?
  @Bindable var navigation: RepositoryNavigationState

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
        List(selection: $navigation.selectedCommitID) {
          ForEach(model.historyRows) { row in
            CommitGraphRowView(
              row: row,
              branchLabels: branchLabelsByTip[row.commit.oid] ?? []
            )
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
    .task(id: reference) {
      navigation.selectedCommitID = nil
      await model.loadHistoryIfNeeded(reference: reference)
      guard !Task.isCancelled, reference != nil else { return }
      navigation.selectedCommitID = model.historyRows.first?.id
    }
  }

  private var branchLabelsByTip: [ObjectID: [HistoryBranchLabel]] {
    var labelsByTip: [ObjectID: [HistoryBranchLabel]] = [:]
    for branch in model.branches {
      labelsByTip[branch.tip, default: []].append(
        HistoryBranchLabel(
          name: branch.name,
          isRemote: false,
          isCurrent: branch.isCurrent
        )
      )
    }
    for remote in model.remotes {
      for branch in model.remoteBranchesByRemote[remote.name] ?? [] {
        labelsByTip[branch.tip, default: []].append(
          HistoryBranchLabel(
            name: branch.name,
            isRemote: true,
            isCurrent: false
          )
        )
      }
    }
    return labelsByTip.mapValues {
      $0.sorted {
        if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
        if $0.isRemote != $1.isRemote { return !$0.isRemote }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
    }
  }

  @ViewBuilder
  private func commitMenu(_ commit: Commit) -> some View {
    RevisionContextMenu(
      model: model,
      navigation: navigation,
      oid: commit.oid,
      startPoint: commit.oid.rawValue,
      targetDescription: "\(commit.oid.shortened) — \(commit.subject)"
    )
    Divider()
    Button("Tag Commit…") {
      navigation.present(.tag(commit))
    }
    .disabled(model.isBusy)
    Divider()
    Button("Interactive Rebase from Here…") {
      navigation.present(.rebase(commit))
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
