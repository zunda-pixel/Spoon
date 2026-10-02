import AppKit
import SpoonCore
import UniformTypeIdentifiers

/// Asks where to save `revision` as an archive, then writes it and shows it
/// in Finder. The file name's extension picks zip, tar.gz, or tar.
@MainActor
func exportArchive(model: RepositoryModel, revision: String, label: String) {
  let panel = NSSavePanel()
  panel.title = "Export Archive"
  panel.prompt = "Export"
  panel.message = "Save the files at \(label) as a .zip, .tar.gz, or .tar archive."
  panel.nameFieldStringValue = "\(model.repository.name)-\(label).zip"
  panel.allowedContentTypes = [.zip, .gzip, .tarArchive]
  panel.allowsOtherFileTypes = true
  panel.isExtensionHidden = false
  panel.canCreateDirectories = true
  guard panel.runModal() == .OK, let destination = panel.url else { return }
  Task {
    if await model.exportArchive(revision: revision, label: label, to: destination) {
      NSWorkspace.shared.activateFileViewerSelecting([destination])
    }
  }
}
