import SpoonCore
import SwiftUI

/// Plans a headless interactive rebase: one row per commit, oldest first
/// (mirroring git's todo order), with a pick/squash/drop/edit action each.
@MainActor
struct RebaseSheet: View {
  let model: RepositoryModel
  let fromCommit: Commit
  @Environment(\.dismiss) private var dismiss
  @State private var plan: RebasePlan?
  @State private var setupErrorMessage: String?

  init(model: RepositoryModel, fromCommit: Commit) {
    self.model = model
    self.fromCommit = fromCommit
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Interactive Rebase")
        .font(.headline)
      if let setupErrorMessage {
        Text(setupErrorMessage)
          .foregroundStyle(.secondary)
          .frame(width: 440, alignment: .leading)
        HStack {
          Spacer()
          Button("Close", role: .cancel) {
            dismiss()
          }
          .keyboardShortcut(.defaultAction)
        }
      } else if let planBinding = Binding($plan) {
        planEditor(planBinding)
      } else {
        ProgressView()
          .frame(width: 480, height: 120)
      }
    }
    .padding(20)
    .task {
      do {
        plan = try await model.rebasePlan(from: fromCommit)
      } catch {
        setupErrorMessage = error.localizedDescription
      }
    }
  }

  private func planEditor(_ plan: Binding<RebasePlan>) -> some View {
    let value = plan.wrappedValue
    return VStack(alignment: .leading, spacing: 10) {
      List {
        ForEach(plan.steps) { $step in
          HStack(spacing: 8) {
            Picker("Action", selection: $step.action) {
              ForEach(RebaseAction.allCases, id: \.self) { action in
                Text(action.rawValue.capitalized)
                  .tag(action)
              }
            }
            .labelsHidden()
            .frame(width: 96)
            Text(step.commit.oid.shortened)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
            Text(step.commit.subject)
              .lineLimit(1)
              .truncationMode(.tail)
          }
          .listRowSeparator(.hidden)
        }
        .onMove { source, destination in
          plan.wrappedValue.steps.move(fromOffsets: source, toOffset: destination)
        }
      }
      .listStyle(.bordered)
      .frame(width: 480, height: min(320, CGFloat(value.steps.count) * 34 + 16))

      Text("Drag rows to reorder commits.")
        .font(.caption)
        .foregroundStyle(.secondary)

      if let validationMessage = validationMessage(for: value) {
        Text(validationMessage)
          .font(.caption)
          .foregroundStyle(.orange)
      }
      HStack {
        Text("\(value.steps.count) commit(s) onto \(value.baseOID?.shortened ?? "root")")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Button("Start Rebase") {
          start(value)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(value.validationError != nil || model.isBusy)
      }
    }
  }

  private func validationMessage(for plan: RebasePlan) -> String? {
    switch plan.validationError {
    case .empty:
      "Keep at least one commit (not everything can be dropped)."
    case .squashWithoutTarget:
      "Squash needs an earlier kept commit to fold into."
    case nil:
      nil
    }
  }

  private func start(_ plan: RebasePlan) {
    guard plan.validationError == nil else { return }
    dismiss()
    Task { await model.interactiveRebase(plan) }
  }
}
