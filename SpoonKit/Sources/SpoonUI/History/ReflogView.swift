import SpoonCore
import SwiftUI

@MainActor
struct ReflogView: View {
  let model: RepositoryModel
  @Binding var selectedOID: String?
  @State private var entries: [ReflogEntry]?
  @State private var errorMessage: String?
  @State private var resettingEntry: ReflogEntry?

  var body: some View {
    Group {
      if let entries {
        if entries.isEmpty {
          ContentUnavailableView(
            "No Reflog Entries",
            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
          )
        } else {
          List(selection: $selectedOID) {
            ForEach(entries) { entry in
              VStack(alignment: .leading, spacing: 2) {
                Text(entry.subject)
                  .lineLimit(1)
                HStack {
                  Text(entry.selector)
                  Text(entry.oid.shortened)
                  Text(entry.date, format: .relative(presentation: .named))
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
              }
              .tag(entry.oid.rawValue)
              .contextMenu {
                Button("Checkout Commit (Detached)") {
                  Task { await model.checkoutRevision(entry.oid) }
                }
                Button("New Branch from Here…") {
                  Task {
                    await model.createBranch(
                      name: "recovered-\(entry.oid.shortened)",
                      from: entry.oid.rawValue,
                      checkout: true
                    )
                  }
                }
                Divider()
                Button("Reset Current Branch to Here…") {
                  resettingEntry = entry
                }
              }
            }
          }
          .listStyle(.plain)
        }
      } else if let errorMessage {
        ContentUnavailableView(
          "Could Not Load Reflog",
          systemImage: "exclamationmark.triangle",
          description: Text(errorMessage)
        )
      } else {
        ProgressView()
      }
    }
    .task(id: model.repository.id) {
      do {
        entries = try await model.reflog()
        selectedOID = entries?.first?.oid.rawValue
      } catch {
        errorMessage = error.localizedDescription
      }
    }
    .sheet(item: $resettingEntry) { entry in
      ResetSheet(
        model: model,
        target: entry.oid,
        targetDescription: "\(entry.selector) — \(entry.subject)"
      )
    }
  }
}
