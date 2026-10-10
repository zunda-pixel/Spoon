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
  @State private var recentAuthors: [CoAuthor] = []
  /// The repository's `commit.template`, which starts every new message.
  @State private var template: CommitTemplate?
  @State private var addingCoAuthor = false

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

      if let template {
        templateHint(template)
      }

      if !model.commitCoAuthors.isEmpty {
        CoAuthorChips(model: model)
      }

      AdaptiveActionsLayout {
        WrappingLayout { options }
        HStack { actions }
      }
    }
    .padding(10)
    .task(id: model.configGeneration) {
      signing = await model.commitSigningConfiguration()
      sign = signing?.signsByDefault ?? false
      let previous = template
      template = await model.commitTemplate()
      // Start from the template, unless the user already typed something.
      if !amend, message.isEmpty || message == previous?.body {
        message = template?.body ?? ""
      }
    }
    .task { recentAuthors = await model.recentAuthors() }
    .sheet(isPresented: $addingCoAuthor) {
      AddCoAuthorSheet(model: model)
    }
  }

  @ViewBuilder
  private var options: some View {
    Toggle("Amend", isOn: $amend)
      .toggleStyle(.checkbox)
    Toggle("Sign Off", isOn: $model.commitSignsOff)
      .toggleStyle(.checkbox)
      .help("Add a Signed-off-by trailer with your name and email. Remembered for this repository.")
    Toggle("Sign", isOn: $sign)
      .toggleStyle(.checkbox)
      .disabled(signing?.canSign == false && !sign)
      .help(signingHelp)
    coAuthorMenu
  }

  /// Credits others with `Co-authored-by:` trailers on the next commit.
  private var coAuthorMenu: some View {
    Menu {
      let remembered = model.rememberedCoAuthors
      ForEach(remembered) { coAuthor in
        Toggle(coAuthor.identity, isOn: coAuthorBinding(coAuthor))
      }
      if !remembered.isEmpty { Divider() }
      let suggestions = recentAuthors.filter { author in
        !remembered.contains { $0.id == author.id }
      }
      if !suggestions.isEmpty {
        Menu("Recent Authors") {
          ForEach(suggestions.prefix(20)) { author in
            Button(author.identity) { model.commitCoAuthors.append(author) }
          }
        }
      }
      Button("Add Co-author…") { addingCoAuthor = true }
      if !remembered.isEmpty {
        Menu("Forget") {
          ForEach(remembered) { coAuthor in
            Button(coAuthor.identity) { model.forget(coAuthor) }
          }
        }
      }
    } label: {
      Label(
        model.commitCoAuthors.isEmpty
          ? "Co-authors" : "Co-authors (\(model.commitCoAuthors.count))",
        systemImage: "person.2")
    }
    .menuStyle(.borderlessButton)
    .help("Credit others with Co-authored-by: lines, which GitHub and GitLab show as co-authors")
  }

  private func coAuthorBinding(_ coAuthor: CoAuthor) -> Binding<Bool> {
    Binding(
      get: { model.commitCoAuthors.contains { $0.id == coAuthor.id } },
      set: { selected in
        model.commitCoAuthors.removeAll { $0.id == coAuthor.id }
        if selected { model.commitCoAuthors.append(coAuthor) }
      }
    )
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
          message = template?.body ?? ""
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

  /// git refuses a message left exactly as the template, and so does Spoon.
  private var isUnchangedTemplate: Bool {
    guard let body = template?.body, !body.isEmpty else { return false }
    return message.trimmingCharacters(in: .whitespacesAndNewlines)
      == body.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func templateHint(_ template: CommitTemplate) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: "doc.text")
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        if isUnchangedTemplate {
          Text("Fill in the template before committing.")
            .foregroundStyle(.orange)
        }
        ForEach(Array(template.comments.prefix(2).enumerated()), id: \.offset) { _, line in
          Text(line)
        }
      }
      Spacer(minLength: 4)
      if !template.body.isEmpty, message != template.body {
        Button("Use Template") { message = template.body }
          .buttonStyle(.link)
          .help("Replace the message with the commit template")
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .lineLimit(2)
    .help(
      (["Commit template: \(template.path)"] + template.comments).joined(separator: "\n"))
  }

  private var canCommit: Bool {
    guard !model.isBusy, !isUnchangedTemplate else { return false }
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

/// The co-authors credited on the next commit, each removable.
@MainActor
private struct CoAuthorChips: View {
  let model: RepositoryModel

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "person.2")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(model.commitCoAuthors) { coAuthor in
            HStack(spacing: 4) {
              Text(coAuthor.name)
              Button("Remove \(coAuthor.name)", systemImage: "xmark.circle.fill") {
                model.commitCoAuthors.removeAll { $0.id == coAuthor.id }
              }
              .labelStyle(.iconOnly)
              .buttonStyle(.borderless)
              .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .help(coAuthor.trailer)
          }
        }
      }
    }
    .font(.callout)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Co-authors")
  }
}

/// Enters a co-author by name and email.
@MainActor
struct AddCoAuthorSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var email = ""

  var body: some View {
    SheetFormLayout(
      title: "Add Co-author",
      subtitle:
        "Credited with a Co-authored-by: line on the next commit. Use the email their GitHub account knows."
    ) {
      Form {
        TextField("Name", text: $name, prompt: Text("Ada Lovelace"))
        TextField("Email", text: $email, prompt: Text("ada@example.com"))
          .onSubmit(add)
      }
      .textFieldStyle(.roundedBorder)
      .frame(width: 360)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Add", action: add)
        .keyboardShortcut(.defaultAction)
        .disabled(coAuthor == nil)
    }
  }

  private var coAuthor: CoAuthor? {
    CoAuthor(identity: "\(name) <\(email)>")
  }

  private func add() {
    guard let coAuthor else { return }
    model.remember([coAuthor])
    model.commitCoAuthors.removeAll { $0.id == coAuthor.id }
    model.commitCoAuthors.append(coAuthor)
    dismiss()
  }
}
