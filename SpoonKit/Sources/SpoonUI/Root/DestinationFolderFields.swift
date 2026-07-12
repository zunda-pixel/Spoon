import SwiftUI
import UniformTypeIdentifiers

/// Location + folder-name form fields shared by the clone and add-worktree
/// sheets. Parents own the state and derive the destination URL / validity.
@MainActor
struct DestinationFolderFields: View {
  @Binding var parentPath: String
  @Binding var folderName: String
  var onSubmitFolderName: () -> Void = {}
  @State private var showingFolderPicker = false

  var body: some View {
    HStack {
      TextField("Location", text: $parentPath)
      Button("Choose…") {
        showingFolderPicker = true
      }
    }
    .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
      if case .success(let url) = result {
        parentPath = url.path
      }
    }
    TextField("Folder name", text: $folderName)
      .onSubmit(onSubmitFolderName)
  }
}
