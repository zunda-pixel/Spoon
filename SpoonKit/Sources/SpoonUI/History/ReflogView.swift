import SpoonCore
import SwiftUI

@MainActor
struct ReflogView: View {
  let model: RepositoryModel
  @Bindable var navigation: RepositoryNavigationState
  @State private var loadState: AsyncLoadState<[ReflogEntry]> = .loading

  var body: some View {
    AsyncContentView(
      state: loadState,
      isEmpty: \.isEmpty,
      content: { reflogList($0) },
      empty: {
        ContentUnavailableView(
          "No Reflog Entries",
          systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        )
      },
      errorTitle: "Could Not Load Reflog"
    )
    .task(id: model.repository.id) {
      await load()
    }
  }

  private func reflogList(_ entries: [ReflogEntry]) -> some View {
    List(selection: $navigation.selectedReflogSelector) {
      ForEach(entries) { entry in
        ReflogRow(entry: entry)
          .tag(entry.selector)
          .contextMenu {
            RevisionContextMenu(
              model: model,
              navigation: navigation,
              oid: entry.oid,
              startPoint: entry.selector,
              targetDescription: "\(entry.selector) — \(entry.subject)"
            )
          }
      }
    }
    .listStyle(.plain)
    .onChange(of: navigation.selectedReflogSelector, initial: true) {
      navigation.selectedReflogOID =
        entries.first {
          $0.selector == navigation.selectedReflogSelector
        }?.oid
    }
  }

  private func load() async {
    do {
      let entries = try await model.reflog()
      loadState = .loaded(entries)
      navigation.selectedReflogSelector = entries.first?.selector
      navigation.selectedReflogOID = entries.first?.oid
    } catch {
      loadState = .failed(error.localizedDescription)
    }
  }
}

private struct ReflogRow: View {
  let entry: ReflogEntry

  var body: some View {
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
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(entry.subject)
    .accessibilityValue(
      "\(entry.selector), commit \(entry.oid.shortened), \(entry.date.formatted(.relative(presentation: .named)))"
    )
    .accessibilityHint("Select to show commit details; open the context menu for revision actions")
  }
}
