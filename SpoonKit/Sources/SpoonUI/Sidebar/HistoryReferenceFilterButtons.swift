import SpoonCore
import SwiftUI

@MainActor
struct HistoryReferenceFilterButtons: View {
  let model: RepositoryModel
  let referenceID: String

  var body: some View {
    HStack(spacing: 2) {
      Button {
        Task { await model.toggleHistoryFocus(referenceID) }
      } label: {
        Image(systemName: model.isHistoryReferenceFocused(referenceID) ? "eye.fill" : "eye")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(
        style(isOn: model.isHistoryReferenceFocused(referenceID))
      )
      .help(model.isHistoryReferenceFocused(referenceID) ? "Stop showing only this reference" : "Show only this reference")
      .accessibilityLabel(model.isHistoryReferenceFocused(referenceID) ? "Stop showing only this reference" : "Show only this reference")

      Button {
        Task { await model.toggleHistoryHidden(referenceID) }
      } label: {
        Image(systemName: model.isHistoryReferenceHidden(referenceID) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(
        style(isOn: model.isHistoryReferenceHidden(referenceID))
      )
      .help(model.isHistoryReferenceHidden(referenceID) ? "Show this reference in history" : "Hide this reference from history")
      .accessibilityLabel(model.isHistoryReferenceHidden(referenceID) ? "Show this reference in history" : "Hide this reference from history")
    }
    .font(.caption)
    .fixedSize()
  }

  /// An active button shows its filled symbol in the primary color: the
  /// accent color would vanish into a selected row's highlight.
  private func style(isOn: Bool) -> AnyShapeStyle {
    isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
  }
}
