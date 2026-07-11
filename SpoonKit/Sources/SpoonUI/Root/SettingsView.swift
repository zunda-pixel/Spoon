public import SwiftUI

import SpoonCore

@MainActor
public struct SettingsView: View {
  public init() {}

  public var body: some View {
    TabView {
      Tab("GitHub", systemImage: "arrow.triangle.pull") {
        GitHubSettingsView()
      }
    }
    .frame(width: 480)
    .scenePadding()
  }
}

/// GitHub auth status + manual PAT fallback. `gh auth token` is preferred
/// and needs no configuration here.
@MainActor
private struct GitHubSettingsView: View {
  @State private var patInput = KeychainTokenProvider.storedToken() ?? ""
  @State private var saveState: String?

  var body: some View {
    Form {
      Section {
        LabeledContent("Preferred sign-in") {
          Text("GitHub CLI (`gh auth login`)")
        }
        Text(
          "Spoon reuses your GitHub CLI login automatically. If you don't use gh, paste a personal access token below (repo scope)."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Personal Access Token (fallback)") {
        SecureField("ghp_…", text: $patInput)
        HStack {
          if let saveState {
            Text(saveState)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Save to Keychain") {
            do {
              try KeychainTokenProvider.save(token: patInput.trimmingCharacters(in: .whitespaces))
              saveState = patInput.isEmpty ? "Token removed." : "Saved."
            } catch {
              saveState = "Could not save: \(error.localizedDescription)"
            }
          }
        }
      }
    }
    .formStyle(.grouped)
  }
}
