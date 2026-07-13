import SpoonCore
import SwiftUI

@MainActor
struct SparseCheckoutSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var isEnabled = false
  @State private var pathsText = ""
  @State private var isLoading = true
  @State private var errorMessage: String?

  private var paths: [String] {
    pathsText.split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Sparse Checkout")
        .font(.headline)
      if isLoading {
        ProgressView()
          .frame(width: 440, height: 180)
      } else {
        Toggle("Limit the working tree to selected folders", isOn: $isEnabled)
        Text("One repository-relative folder per line (cone mode).")
          .font(.caption)
          .foregroundStyle(.secondary)
        TextEditor(text: $pathsText)
          .font(.body.monospaced())
          .frame(width: 440, height: 180)
          .border(.separator)
          .disabled(!isEnabled)
        if let errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.red)
        }
        HStack {
          Spacer()
          Button("Cancel", role: .cancel) {
            dismiss()
          }
          Button("Apply") {
            let enabled = isEnabled
            let paths = paths
            dismiss()
            Task {
              if enabled {
                await model.setSparseCheckout(paths: paths)
              } else {
                await model.disableSparseCheckout()
              }
            }
          }
          .keyboardShortcut(.defaultAction)
          .disabled(isEnabled && paths.isEmpty)
        }
      }
    }
    .padding(20)
    .task {
      do {
        let current = try await model.sparseCheckoutPaths()
        isEnabled = current != nil
        pathsText = current?.joined(separator: "\n") ?? ""
      } catch {
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }
}
