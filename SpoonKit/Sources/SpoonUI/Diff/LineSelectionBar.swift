import SwiftUI

/// Chrome shown above a diff while lines are selected: count, the owner's
/// action buttons, and Deselect. Owners supply only the actions.
@MainActor
struct LineSelectionBar<Actions: View>: View {
  let selection: DiffLineSelection
  let onDeselect: () -> Void
  private let actions: Actions

  init(
    selection: DiffLineSelection,
    onDeselect: @escaping () -> Void,
    @ViewBuilder actions: () -> Actions
  ) {
    self.selection = selection
    self.onDeselect = onDeselect
    self.actions = actions()
  }

  var body: some View {
    HStack(spacing: 10) {
      Text("\(selection.offsets.count) line(s) selected")
        .font(.callout)
        .foregroundStyle(.secondary)
      actions
        .controlSize(.small)
      Button("Deselect", action: onDeselect)
        .controlSize(.small)
      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.bar)
  }
}
