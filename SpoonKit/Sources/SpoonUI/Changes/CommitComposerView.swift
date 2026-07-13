import SpoonCore
import SwiftUI

/// Message editor + commit button pinned under the Changes list.
@MainActor
struct CommitComposerView: View {
  let model: RepositoryModel
  @State private var message = ""
  @State private var amend = false

  init(model: RepositoryModel) {
    self.model = model
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextEditor(text: $message)
        .font(.body)
        .frame(minHeight: 60, maxHeight: 120)
        .scrollContentBackground(.hidden)
        .padding(6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("Commit message")
        .accessibilityHint("Enter the message for the staged changes")
        .overlay(alignment: .topLeading) {
          if message.isEmpty {
            Text("Commit message")
              .foregroundStyle(.tertiary)
              .padding(.top, 6 + 8)
              .padding(.leading, 6 + 5)
              .allowsHitTesting(false)
          }
        }

      HStack {
        Toggle("Amend", isOn: $amend)
          .toggleStyle(.checkbox)

        Menu {
          ForEach(AIProviderID.allCases) { provider in
            Button("Generate with \(provider.displayName)") {
              generate(with: provider)
            }
          }
        } label: {
          if case .generatingCommitMessage = model.aiActivity {
            Label("Generating…", systemImage: "sparkles")
          } else {
            Label("Generate", systemImage: "sparkles")
          }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.aiActivity != nil || (model.status?.stagedEntries.isEmpty ?? true))
        .help("Generate a commit message from the staged changes")

        Spacer()

        if model.isBusy || model.aiActivity == .generatingCommitMessage(.claudeCode)
          || model.aiActivity == .generatingCommitMessage(.codex)
        {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Commit operation in progress")
        }

        Button("Commit") {
          Task {
            if await model.commit(message: message, amend: amend) {
              message = ""
              amend = false
            }
          }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!canCommit)
      }
    }
    .padding(10)
  }

  private var canCommit: Bool {
    guard !model.isBusy else { return false }
    let hasMessage = !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let hasStaged =
      !(model.status?.stagedEntries.isEmpty ?? true)
      || !(model.status?.conflictedEntries.isEmpty ?? true)
    return hasMessage && (hasStaged || amend)
  }

  private func generate(with provider: AIProviderID) {
    Task {
      if let generated = await model.generateCommitMessage(with: provider) {
        message = generated
      }
    }
  }
}
