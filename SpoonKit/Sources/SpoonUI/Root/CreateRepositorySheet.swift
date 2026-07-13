import SpoonCore
import SwiftUI

@MainActor
struct CreateRepositorySheet: View {
  let onOpen: (Repository.ID) -> Void
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @State private var parentPath: String
  @State private var folderName = ""
  @State private var initialBranch = "main"
  @State private var errorMessage: String?
  @State private var createTask: Task<Void, Never>?

  init(onOpen: @escaping (Repository.ID) -> Void) {
    self.onOpen = onOpen
    let home = FileManager.default.homeDirectoryForCurrentUser
    let developer = home.appending(path: "Developer")
    self._parentPath = State(
      initialValue: FileManager.default.fileExists(atPath: developer.path)
        ? developer.path
        : home.appending(path: "Documents").path
    )
  }

  private var isCreating: Bool { createTask != nil }

  private var destination: URL {
    URL(filePath: parentPath, directoryHint: .isDirectory).appending(path: folderName)
  }

  private var isValid: Bool {
    !parentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !initialBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !FileManager.default.fileExists(atPath: destination.path)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Create Repository")
        .font(.headline)

      Form {
        DestinationFolderFields(
          parentPath: $parentPath,
          folderName: $folderName,
          onSubmitFolderName: create
        )
        TextField("Initial branch", text: $initialBranch)
          .onSubmit(create)
      }
      .textFieldStyle(.roundedBorder)
      .frame(width: 440)
      .disabled(isCreating)

      if isCreating {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Creating repository…")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .frame(width: 440, alignment: .leading)
      }

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          if let createTask {
            createTask.cancel()
          } else {
            dismiss()
          }
        }
        Button("Create", action: create)
          .keyboardShortcut(.defaultAction)
          .disabled(!isValid || isCreating)
      }
    }
    .padding(20)
  }

  private func create() {
    guard isValid, !isCreating else { return }
    errorMessage = nil
    let destination = destination
    let branch = initialBranch.trimmingCharacters(in: .whitespacesAndNewlines)
    createTask = Task {
      do {
        let repository = try await appModel.createRepository(
          at: destination,
          initialBranch: branch
        )
        createTask = nil
        dismiss()
        onOpen(repository.id)
      } catch {
        try? FileManager.default.removeItem(at: destination)
        if !(error is CancellationError) {
          errorMessage = error.localizedDescription
        }
        createTask = nil
      }
    }
  }
}
