import SpoonCore
import SwiftUI

@MainActor
struct EditRemoteSheet: View {
  let model: RepositoryModel
  let remote: Remote
  @Environment(\.dismiss) private var dismiss
  @State private var fetchURL: String
  @State private var pushURL: String

  init(model: RepositoryModel, remote: Remote) {
    self.model = model
    self.remote = remote
    self._fetchURL = State(initialValue: remote.fetchURL)
    self._pushURL = State(initialValue: remote.pushURL ?? "")
  }

  private var isValid: Bool {
    !fetchURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Edit Remote “\(remote.name)”")
        .font(.headline)
      Form {
        TextField("Fetch URL", text: $fetchURL)
        TextField(
          "Push URL",
          text: $pushURL,
          prompt: Text("Same as fetch URL")
        )
      }
      .textFieldStyle(.roundedBorder)
      .frame(width: 440)

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Button("Save") {
          let fetch = fetchURL.trimmingCharacters(in: .whitespacesAndNewlines)
          let push = pushURL.trimmingCharacters(in: .whitespacesAndNewlines)
          dismiss()
          Task {
            await model.setRemoteURL(
              name: remote.name,
              fetchURL: fetch,
              pushURL: push.isEmpty ? nil : push
            )
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!isValid || model.isBusy)
      }
    }
    .padding(20)
  }
}
