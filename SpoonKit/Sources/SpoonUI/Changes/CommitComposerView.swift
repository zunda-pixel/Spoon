import SpoonCore
import SwiftUI

/// Message editor + commit button pinned under the Changes list.
@MainActor
struct CommitComposerView: View {
  @Bindable var model: RepositoryModel
  @State private var message = ""
  @State private var amend = false
  @State private var sign = false
  /// `nil` until loaded, or when git config can't be read.
  @State private var signing: CommitSigningConfiguration?

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

      // The options move to their own row when the column is too narrow.
      ViewThatFits(in: .horizontal) {
        HStack {
          options
          actions
        }
        VStack(alignment: .leading, spacing: 8) {
          HStack { options }
          HStack { actions }
        }
      }
    }
    .padding(10)
    .task(id: model.configGeneration) {
      signing = await model.commitSigningConfiguration()
      sign = signing?.signsByDefault ?? false
    }
  }

  @ViewBuilder
  private var options: some View {
    Toggle("Amend", isOn: $amend)
      .toggleStyle(.checkbox)
      .fixedSize()
    Toggle("Sign Off", isOn: $model.commitSignsOff)
      .toggleStyle(.checkbox)
      .fixedSize()
      .help("Add a Signed-off-by trailer with your name and email. Remembered for this repository.")
    Toggle("Sign", isOn: $sign)
      .toggleStyle(.checkbox)
      .fixedSize()
      .disabled(signing?.canSign == false && !sign)
      .help(signingHelp)
  }

  @ViewBuilder
  private var actions: some View {
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
        if await model.commit(message: message, options: commitOptions) {
          message = ""
          amend = false
          sign = signing?.signsByDefault ?? false
        }
      }
    }
    .keyboardShortcut(.return, modifiers: .command)
    .disabled(!canCommit)
  }

  private var signingHelp: String {
    guard let signing else { return "Sign this commit with your configured key" }
    guard signing.canSign else {
      return "Set user.signingKey to sign commits with \(signing.format.displayName)"
    }
    let key = signing.key.map { " \($0)" } ?? ""
    let prefix = signing.signsByDefault ? "Signed by default (commit.gpgSign). " : ""
    return "\(prefix)Sign this commit with your \(signing.format.displayName) key\(key)"
  }

  private var commitOptions: CommitOptions {
    let signsByDefault = signing?.signsByDefault ?? false
    return CommitOptions(
      amend: amend,
      signOff: model.commitSignsOff,
      signing: sign == signsByDefault ? .configured : sign ? .sign : .doNotSign
    )
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
