import SpoonCore
import SwiftUI

@MainActor
struct HistoryListView: View {
  let model: RepositoryModel
  let focus: HistoryFocus?
  @Bindable var navigation: RepositoryNavigationState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ScrollViewReader { proxy in
      Group {
        if model.historyRows.isEmpty {
          if model.isLoadingHistory {
            ProgressView()
          } else {
            ContentUnavailableView(
              "No Commits",
              systemImage: "clock",
              description: Text("This repository has no commits yet.")
            )
          }
        } else {
          List(selection: $navigation.selectedCommitID) {
            ForEach(model.historyRows) { row in
              CommitGraphRowView(
                row: row,
                referenceLabels: referenceLabelsByOID[row.commit.oid] ?? [],
                selectedReference: focus?.reference
              )
              .tag(row.id)
              .id(row.id)
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
      .task(id: focus) {
        await loadHistoryAndFocus(using: proxy)
      }
    }
  }

  private var referenceLabelsByOID: [ObjectID: [HistoryReferenceLabel]] {
    HistoryReferenceLabelBuilder.build(
      branches: model.branches,
      remoteBranchesByRemote: model.remoteBranchesByRemote,
      worktrees: model.worktrees,
      tags: model.tags,
      stashes: model.stashes,
      activeWorktreeRoot: model.repository.rootURL,
      selectedReference: focus?.reference
    )
  }

  private func loadHistoryAndFocus(using proxy: ScrollViewProxy) async {
    guard await waitForCurrentHistoryLoad() else { return }
    await model.loadHistoryIfNeeded()
    guard await waitForCurrentHistoryLoad(), let focus else { return }

    if !model.historyRows.contains(where: { $0.commit.oid == focus.tip }) {
      guard await model.ensureCommitLoaded(focus.tip) else { return }
    }

    guard
      !Task.isCancelled,
      model.historyRows.contains(where: { $0.commit.oid == focus.tip })
    else {
      return
    }

    navigation.selectedCommitID = focus.tip.rawValue
    await Task.yield()
    guard !Task.isCancelled else { return }
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
      proxy.scrollTo(focus.tip.rawValue, anchor: .center)
    }
  }

  private func waitForCurrentHistoryLoad() async -> Bool {
    while model.isLoadingHistory {
      do {
        try await Task.sleep(for: .milliseconds(20))
      } catch {
        return false
      }
    }
    return !Task.isCancelled
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
