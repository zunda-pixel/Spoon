import SpoonCore
import SwiftUI

@MainActor
struct RevisionContextMenu: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  let oid: ObjectID
  let startPoint: String
  let targetDescription: String

  var body: some View {
    Button("Checkout Commit (Detached)") {
      Task { await model.checkoutRevision(oid) }
    }
    .disabled(model.isBusy || model.isSequencing)
    Button("New Branch from Here…") {
      navigation.present(.newBranch(startPoint: startPoint))
    }
    .disabled(model.isBusy)
    Button("Reset Current Branch to Here…") {
      navigation.present(.reset(target: oid, description: targetDescription))
    }
    .disabled(model.isBusy || model.isSequencing)
  }
}
