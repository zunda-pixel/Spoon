import AppKit
import SpoonCore
import SwiftUI

@MainActor
struct ChangeFileContextMenu: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  let entry: FileStatusEntry
  let area: RepositoryModel.ChangeArea
  let targets: Set<RepositoryModel.FileSelection>
  @Binding var confirmingDiscard: RepositoryModel.FileSelection?
  let moveFiles: (_ stagePaths: [String], _ unstagePaths: [String]) -> Void

  var body: some View {
    if targets.count > 1 {
      multiTargetActions
    } else {
      singleTargetActions
    }
  }

  @ViewBuilder
  private var multiTargetActions: some View {
    let stageable = targets.filter { $0.area != .staged }
    let staged = targets.filter { $0.area == .staged }
    if !stageable.isEmpty {
      Button("Stage (\(stageable.count))") {
        moveFiles(stageable.map(\.path), [])
      }
    }
    if !staged.isEmpty {
      Button("Unstage (\(staged.count))") {
        moveFiles([], staged.map(\.path))
      }
    }
  }

  @ViewBuilder
  private var singleTargetActions: some View {
    switch area {
    case .staged:
      Button("Unstage") { moveFiles([], [entry.path]) }
    case .unstaged:
      Button("Stage") { moveFiles([entry.path], []) }
      Button("Discard Changes…", role: .destructive) {
        confirmingDiscard = RepositoryModel.FileSelection(path: entry.path, area: area)
      }
    case .untracked:
      Button("Stage") { moveFiles([entry.path], []) }
      Button("Delete File…", role: .destructive) {
        confirmingDiscard = RepositoryModel.FileSelection(path: entry.path, area: area)
      }
    case .conflicted:
      Button("Mark Resolved (Stage)") { moveFiles([entry.path], []) }
    }
    if area != .untracked {
      Divider()
      Button("Show File History…") {
        navigation.present(.fileHistory(path: entry.path))
      }
    }
    if FileManager.default.fileExists(atPath: fileURL.path) {
      Divider()
      Button("Open") {
        NSWorkspace.shared.open(fileURL)
      }
      Button("Reveal in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
      }
    }
  }

  private var fileURL: URL {
    model.repository.rootURL.appending(path: entry.path)
  }
}
