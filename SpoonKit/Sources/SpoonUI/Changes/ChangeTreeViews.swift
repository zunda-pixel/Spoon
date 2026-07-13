import SpoonCore
import SwiftUI

@MainActor
struct ChangeTreeNodeView<Row: View>: View {
  let node: FileTreeNode
  let isExpanded: (FileTreeNode) -> Binding<Bool>
  let fileRow: (FileStatusEntry, String) -> Row
  let onDrop: ([ChangePathsPayload]) -> Void

  var body: some View {
    if let entry = node.entry {
      fileRow(entry, node.name)
    } else if let children = node.children {
      DisclosureGroup(isExpanded: isExpanded(node)) {
        ForEach(children) { child in
          ChangeTreeNodeView(
            node: child,
            isExpanded: isExpanded,
            fileRow: fileRow,
            onDrop: onDrop
          )
        }
      } label: {
        Button {
          isExpanded(node).wrappedValue.toggle()
        } label: {
          Label(node.name, systemImage: "folder")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(node.name)
        .accessibilityValue(isExpanded(node).wrappedValue ? "Expanded folder" : "Collapsed folder")
        .accessibilityHint("Shows or hides files in this folder")
        .dropDestination(for: ChangePathsPayload.self) { items, _ in
          onDrop(items)
        }
      }
    }
  }
}

@MainActor
struct FileStatusRow: View {
  let entry: FileStatusEntry
  var displayName: String

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 1) {
        Text(displayName)
          .lineLimit(1)
          .truncationMode(.middle)
        if let originalPath = entry.originalPath {
          Text("from \(originalPath)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    } icon: {
      statusIcon
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(displayName)
    .accessibilityValue(statusDescription)
  }

  @ViewBuilder
  private var statusIcon: some View {
    if entry.conflict != nil {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    } else if entry.isUntracked {
      Image(systemName: "questionmark.circle")
        .foregroundStyle(.secondary)
    } else {
      switch entry.staged ?? entry.unstaged {
      case .added:
        Image(systemName: "plus.circle.fill").foregroundStyle(.green)
      case .deleted:
        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
      case .renamed, .copied:
        Image(systemName: "arrow.right.circle.fill").foregroundStyle(.blue)
      case .modified, .typeChanged, nil:
        Image(systemName: "pencil.circle.fill").foregroundStyle(.yellow)
      }
    }
  }

  private var statusDescription: String {
    let status: String
    if entry.conflict != nil {
      status = "Conflicted"
    } else if entry.isUntracked {
      status = "Untracked"
    } else {
      switch entry.staged ?? entry.unstaged {
      case .added: status = "Added"
      case .deleted: status = "Deleted"
      case .renamed: status = "Renamed"
      case .copied: status = "Copied"
      case .modified: status = "Modified"
      case .typeChanged: status = "Type changed"
      case nil: status = "Changed"
      }
    }
    if let originalPath = entry.originalPath {
      return "\(status), from \(originalPath)"
    }
    return status
  }
}
