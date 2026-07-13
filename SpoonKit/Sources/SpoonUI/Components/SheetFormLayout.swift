import SwiftUI

struct SheetFormLayout<Content: View, Actions: View>: View {
  let title: String
  var subtitle: String?
  @ViewBuilder let content: Content
  @ViewBuilder let actions: Actions

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.headline)
        .lineLimit(1)
      if let subtitle {
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      content
      HStack {
        Spacer()
        actions
      }
    }
    .padding(20)
  }
}
