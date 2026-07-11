import SpoonCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct WelcomeView: View {
  @Environment(AppModel.self) private var appModel
  @State private var isChoosingFolder = false
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
