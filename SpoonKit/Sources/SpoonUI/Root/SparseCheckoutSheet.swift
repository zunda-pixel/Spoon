import SpoonCore
import SwiftUI

@MainActor
struct SparseCheckoutSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var isCurrentlyEnabled = false
  @State private var pathsText = ""
  @State private var isLoading = true
  @State private var errorMessage: String?

  private var paths: [String] {
    pathsText.split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  var body: some View {
    SheetFormLayout(
      title: "Sparse Checkout",
      subtitle: "One repository-relative folder per line (cone mode)."
    ) {
      if isLoading {
        ProgressView()
          .frame(width: 440, height: 180)
      } else {
        TextEditor(text: $pathsText)
          .font(.body.monospaced())
          .frame(width: 440, height: 180)
          .border(.separator)
        if paths.isEmpty {
          Label(
            "Enter at least one path. Restoring the full working tree uses Disable Sparse Checkout.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(.red)
          .frame(width: 440, alignment: .leading)
        } else if let errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
    } actions: {
      if isCurrentlyEnabled {
        Button("Disable Sparse Checkout", role: .destructive) {
          dismiss()
          Task { await model.disableSparseCheckout() }
        }
        .disabled(isLoading)
      }
      Button("Cancel", role: .cancel) {
        dismiss()
      }
      Button(isCurrentlyEnabled ? "Update Paths" : "Enable Sparse Checkout") {
        let paths = paths
        guard !paths.isEmpty else {
          errorMessage = SparseCheckoutError.emptyPaths.localizedDescription
          return
        }
        dismiss()
        Task { await model.setSparseCheckout(paths: paths) }
      }
      .keyboardShortcut(.defaultAction)
      .disabled(isLoading || paths.isEmpty)
    }
    .task {
      do {
        let current = try await model.sparseCheckoutPaths()
        isCurrentlyEnabled = current != nil
        pathsText = current?.joined(separator: "\n") ?? ""
      } catch {
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }
}
