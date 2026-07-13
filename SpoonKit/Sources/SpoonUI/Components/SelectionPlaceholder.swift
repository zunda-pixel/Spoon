import SwiftUI

struct SelectionPlaceholder: View {
  var title = "No Selection"
  var systemImage = "doc.text.magnifyingglass"
  var description = "Select a file or commit to see its changes."

  var body: some View {
    ContentUnavailableView(
      title,
      systemImage: systemImage,
      description: Text(description)
    )
  }
}
