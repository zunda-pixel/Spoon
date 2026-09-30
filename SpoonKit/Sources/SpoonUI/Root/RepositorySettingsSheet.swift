import SpoonCore
import SwiftUI

/// Edits this repository's own `git config` values. An empty field or
/// "Default" removes the local value, so the user's or system setting
/// (shown as the placeholder) applies again.
@MainActor
struct RepositorySettingsSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var loadState: AsyncLoadState<RepositoryConfig> = .loading
  /// Local values being edited; a missing key means "inherit".
  @State private var draft: [RepositorySetting: String] = [:]
  @State private var confirmingForgetAll = false

  var body: some View {
    VStack(spacing: 0) {
      Text("Settings for \(model.repository.name)")
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .top], 16)
      AsyncContentView(
        state: loadState,
        isEmpty: { _ in false },
        content: { form($0) },
        empty: { EmptyView() },
        errorTitle: "Could Not Read Settings"
      )
      Divider()
      HStack {
        Text("Saved in this repository’s .git/config. Empty fields use your global setting.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
        Button("Save", action: save)
          .keyboardShortcut(.defaultAction)
          .disabled(changes.isEmpty || model.isBusy)
      }
      .padding(12)
    }
    .frame(width: 560, height: 620)
    .task {
      do {
        let config = try await model.repositoryConfig()
        var values: [RepositorySetting: String] = [:]
        for setting in RepositorySetting.allCases {
          values[setting] = config.localValue(setting)
        }
        draft = values
        loadState = .loaded(config)
      } catch {
        loadState = .failed(error.localizedDescription)
      }
    }
  }

  private func form(_ config: RepositoryConfig) -> some View {
    Form {
      Section("Identity") {
        text(.userName, "Name", config)
        text(.userEmail, "Email", config)
      }
      Section("Pull and Push") {
        choice(
          .pullRebase, "Pull strategy", config,
          options: [
            ("false", "Merge"), ("true", "Rebase"), ("merges", "Rebase, keeping merges"),
          ])
        choice(
          .pullFastForward, "Fast-forward", config,
          options: [("only", "Only fast-forward"), ("true", "When possible"), ("false", "Never")])
        toggle(.fetchPrune, "Prune deleted remote branches on fetch", config)
        toggle(.pushAutoSetupRemote, "Push new branches to a same-named upstream", config)
      }
      Section("Signing") {
        toggle(.commitSign, "Sign commits", config)
        toggle(.tagSign, "Sign annotated tags", config)
        choice(
          .signingFormat, "Format", config,
          options: [("openpgp", "GPG"), ("ssh", "SSH"), ("x509", "X.509")])
        text(.signingKey, "Signing key", config, prompt: "Key ID or path to an SSH public key")
      }
      Section("Conflicts") {
        toggle(.rerereEnabled, "Remember how conflicts were resolved (rerere)", config)
        toggle(.rerereAutoUpdate, "Stage files resolved from a recording", config)
        Button("Forget All Recorded Resolutions…") { confirmingForgetAll = true }
          .disabled(model.isBusy)
          .confirmationDialog(
            "Forget every recorded conflict resolution?", isPresented: $confirmingForgetAll
          ) {
            Button("Forget All", role: .destructive) {
              Task { await model.forgetAllRecordedResolutions() }
            }
          } message: {
            Text("Conflicts rerere would have resolved from these recordings have to be resolved by hand again.")
          }
      }
      Section("Blame") {
        text(
          .blameIgnoreRevsFile, "Ignore commits listed in", config,
          prompt: BlameOptions.conventionalIgnoreRevsFile)
      }
    }
    .formStyle(.grouped)
  }

  // MARK: - Rows

  private func text(
    _ setting: RepositorySetting, _ label: String, _ config: RepositoryConfig,
    prompt: String? = nil
  ) -> some View {
    TextField(
      label,
      text: Binding(
        get: { draft[setting] ?? "" },
        set: { draft[setting] = $0.isEmpty ? nil : $0 }
      ),
      prompt: Text(inherited(setting, config) ?? prompt ?? "Not set")
    )
  }

  private func toggle(
    _ setting: RepositorySetting, _ label: String, _ config: RepositoryConfig
  ) -> some View {
    choice(setting, label, config, options: [("true", "On"), ("false", "Off")])
  }

  private func choice(
    _ setting: RepositorySetting, _ label: String, _ config: RepositoryConfig,
    options: [(value: String, title: String)]
  ) -> some View {
    Picker(label, selection: Binding(get: { draft[setting] }, set: { draft[setting] = $0 })) {
      Text(defaultTitle(setting, config, options: options)).tag(String?.none)
      Divider()
      ForEach(options, id: \.value) { option in
        Text(option.title).tag(String?.some(option.value))
      }
      // Keep a value set outside Spoon selectable instead of losing it.
      if let current = config.localValue(setting),
        !options.contains(where: { $0.value == current.lowercased() })
      {
        Text(current).tag(String?.some(current))
      }
    }
  }

  /// "Default (Rebase, from global)" or just "Default".
  private func defaultTitle(
    _ setting: RepositorySetting, _ config: RepositoryConfig,
    options: [(value: String, title: String)]
  ) -> String {
    guard let entry = config.inheritedValue(setting) else { return "Default" }
    let title =
      options.first { $0.value == Self.normalized(entry.value) }?.title ?? entry.value
    return "Default (\(title), from \(entry.scope))"
  }

  private func inherited(_ setting: RepositorySetting, _ config: RepositoryConfig) -> String? {
    config.inheritedValue(setting).map { "\($0.value) (\($0.scope))" }
  }

  /// git's boolean spellings, folded to `true` / `false`.
  private static func normalized(_ value: String) -> String {
    switch value.lowercased() {
    case "yes", "on", "1": "true"
    case "no", "off", "0": "false"
    default: value.lowercased()
    }
  }

  // MARK: - Saving

  /// Settings whose local value differs from what the repository has.
  private var changes: [RepositorySetting: String?] {
    guard case .loaded(let config) = loadState else { return [:] }
    var changes: [RepositorySetting: String?] = [:]
    for setting in RepositorySetting.allCases {
      let value = draft[setting]?.trimmingCharacters(in: .whitespaces)
      let edited = value?.isEmpty == false ? value : nil
      if edited != config.localValue(setting) {
        changes[setting] = .some(edited)
      }
    }
    return changes
  }

  private func save() {
    let changes = changes
    dismiss()
    Task { await model.saveRepositoryConfig(changes) }
  }
}
