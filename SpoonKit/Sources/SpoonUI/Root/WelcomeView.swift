import SpoonCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct WelcomeView: View {
  @Environment(AppModel.self) private var appModel
  @State private var isChoosingFolder = false
  @State private var showingCreateSheet = false
  @State private var showingCloneSheet = false
  @State private var openErrorMessage: String?

  let onOpen: (Repository.ID) -> Void

  init(onOpen: @escaping (Repository.ID) -> Void) {
    self.onOpen = onOpen
  }

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 12) {
        Image(systemName: "fork.knife")
          .font(.system(size: 56))
          .foregroundStyle(.tint)
        Text("Spoon")
          .font(.largeTitle.bold())
        Text("An AI-first Git client")
          .foregroundStyle(.secondary)

        Button {
          isChoosingFolder = true
        } label: {
          Label("Open Repository…", systemImage: "folder")
        }
        .controlSize(.large)
        .keyboardShortcut("o", modifiers: .command)
        .padding(.top, 16)

        Button {
          showingCreateSheet = true
        } label: {
          Label("Create Repository…", systemImage: "plus.rectangle.on.folder")
        }
        .controlSize(.large)
        .keyboardShortcut("n", modifiers: [.command, .shift])

        Button {
          showingCloneSheet = true
        } label: {
          Label("Clone Repository…", systemImage: "square.and.arrow.down.on.square")
        }
        .controlSize(.large)
        .keyboardShortcut("o", modifiers: [.command, .shift])
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      recentsList
        .frame(width: 280)
        .background(.background.secondary)
    }
    .frame(minWidth: 640, minHeight: 400)
    .fileImporter(
      isPresented: $isChoosingFolder,
      allowedContentTypes: [.folder]
    ) { result in
      if case .success(let url) = result {
        open(url)
      }
    }
    .sheet(isPresented: $showingCreateSheet) {
      CreateRepositorySheet(onOpen: onOpen)
    }
    .sheet(isPresented: $showingCloneSheet) {
      CloneRepositorySheet(onOpen: onOpen)
    }
    .alert(
      "Could Not Open Repository",
      isPresented: .init(
        get: { openErrorMessage != nil },
        set: { if !$0 { openErrorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(openErrorMessage ?? "")
    }
  }

  private var recentsList: some View {
    List {
      Section("Recent") {
        if appModel.recentRepositories.isEmpty {
          Text("No recent repositories")
            .foregroundStyle(.secondary)
        }
        ForEach(appModel.recentRepositories) { repository in
          Button {
            onOpen(repository.id)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(repository.name)
                .fontWeight(.medium)
              Text(repository.id)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            // Fill the row and make the whole area hit-testable — a plain
            // button is otherwise only clickable on the text itself.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button("Remove from Recents") {
              appModel.removeRecent(repository)
            }
          }
        }
      }
    }
    .scrollContentBackground(.hidden)
  }

  private func open(_ url: URL) {
    Task {
      do {
        let repository = try await appModel.openRepository(at: url)
        onOpen(repository.id)
      } catch {
        openErrorMessage = error.localizedDescription
      }
    }
  }
}

@MainActor
private struct CloneRepositorySheet: View {
  let onOpen: (Repository.ID) -> Void
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @State private var remoteURL = ""
  @State private var parentPath: String
  @State private var folderName = ""
  @State private var userEditedName = false
  @State private var filterBlobNone = false
  @State private var shallowClone = false
  @State private var depth = 1
  @State private var singleBranch = false
  @State private var branchName = ""
  @State private var progressText = ""
  @State private var errorMessage: String?
  @State private var cloneTask: Task<Void, Never>?

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

  private var isCloning: Bool { cloneTask != nil }

  private var destination: URL {
    URL(filePath: parentPath, directoryHint: .isDirectory).appending(path: folderName)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Clone Repository")
        .font(.headline)
      Form {
        TextField(
          "URL", text: $remoteURL,
          prompt: Text("https://github.com/owner/repo.git")
        )
        .onChange(of: remoteURL) {
          guard !userEditedName else { return }
          folderName = Self.derivedName(from: remoteURL)
        }
        .onSubmit(clone)
        DestinationFolderFields(
          parentPath: $parentPath,
          folderName: Binding(
            get: { folderName },
            set: { folderName = $0; userEditedName = true }
          )
        )
        CloneOptionsFields(
          filterBlobNone: $filterBlobNone,
          shallowClone: $shallowClone,
          depth: $depth,
          singleBranch: $singleBranch,
          branchName: $branchName
        )
      }
      .textFieldStyle(.roundedBorder)
      .frame(width: 440)
      .disabled(isCloning)

      if isCloning {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(progressText)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
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
          if let cloneTask {
            cloneTask.cancel()
          } else {
            dismiss()
          }
        }
        Button("Clone", action: clone)
          .keyboardShortcut(.defaultAction)
          .disabled(!isValid || isCloning)
      }
    }
    .padding(20)
  }

  /// `https://github.com/owner/repo.git` / `git@github.com:owner/repo.git`
  /// → `repo`.
  private static func derivedName(from url: String) -> String {
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    let tail = trimmed.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
    return tail.hasSuffix(".git") ? String(tail.dropLast(4)) : tail
  }

  private var isValid: Bool {
    !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !parentPath.trimmingCharacters(in: .whitespaces).isEmpty
      && !folderName.trimmingCharacters(in: .whitespaces).isEmpty
      && !FileManager.default.fileExists(atPath: destination.path)
      && (!shallowClone || depth >= 1)
  }

  private func clone() {
    guard isValid, !isCloning else { return }
    errorMessage = nil
    progressText = "Starting clone…"
    let destination = destination
    let url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let options = CloneOptions(
      filterBlobNone: filterBlobNone,
      depth: shallowClone ? depth : nil,
      singleBranch: singleBranch,
      branch: branchName.isEmpty ? nil : branchName
    )
    cloneTask = Task {
      do {
        let repository = try await appModel.cloneRepository(
          from: url, to: destination, options: options
        ) { line in
          Task { @MainActor in
            progressText = line
          }
        }
        cloneTask = nil
        dismiss()
        onOpen(repository.id)
      } catch {
        // Remove git's partial folder so a retry can reuse the name.
        try? FileManager.default.removeItem(at: destination)
        if !(error is CancellationError) {
          errorMessage = error.localizedDescription
        }
        cloneTask = nil
      }
    }
  }
}
