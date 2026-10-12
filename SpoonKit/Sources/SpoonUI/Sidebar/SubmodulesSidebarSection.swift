import AppKit
import SpoonCore
import SwiftUI

@MainActor
struct SubmodulesSidebarSection: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  @Bindable var expansion: SidebarExpansionState
  let searchText: String
  @State private var pending: PendingSubmoduleAction?

  var body: some View {
    if !model.submodules.isEmpty {
      Section(isExpanded: $expansion.submodules) {
        if filteredSubmodules.isEmpty {
          Label("No matching submodules", systemImage: "magnifyingglass")
            .foregroundStyle(.tertiary)
        }
        ForEach(filteredSubmodules) { submodule in
          SubmoduleRow(submodule: submodule)
            .contextMenu {
              SubmoduleContextMenu(
                model: model,
                navigation: navigation,
                submodule: submodule,
                confirm: { pending = $0 }
              )
            }
        }
      } header: {
        Text("Submodules")
      }
      .onChange(of: searchText) {
        if searchText.hasSidebarSearchQuery {
          expansion.submodules = true
        }
      }
      .confirmationDialog(
        pending?.title ?? "",
        isPresented: .init(get: { pending != nil }, set: { if !$0 { pending = nil } })
      ) {
        if let pending {
          Button(pending.actionTitle, role: .destructive) { run(pending, discardingChanges: false) }
          Button("\(pending.actionTitle) and Discard Local Changes", role: .destructive) {
            run(pending, discardingChanges: true)
          }
        }
      } message: {
        Text(pending?.message ?? "")
      }
    }
  }

  private func run(_ action: PendingSubmoduleAction, discardingChanges: Bool) {
    Task {
      switch action {
      case .deinitialize(let submodule):
        await model.deinitializeSubmodule(submodule, discardingChanges: discardingChanges)
      case .remove(let submodule):
        await model.removeSubmodule(submodule, discardingChanges: discardingChanges)
      }
    }
  }

  private var filteredSubmodules: [Submodule] {
    model.submodules.filter {
      $0.path.matchesSidebarSearch(searchText) || ($0.url ?? "").matchesSidebarSearch(searchText)
    }
  }
}

@MainActor
private struct SubmoduleRow: View {
  let submodule: Submodule

  var body: some View {
    Label {
      HStack {
        Text(submodule.path)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 4)
        stateLabel
      }
    } icon: {
      Image(systemName: "shippingbox")
    }
    .help(help)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(submodule.path)
    .accessibilityValue(stateDescription)
    .accessibilityHint("Open the context menu for submodule actions")
  }

  @ViewBuilder
  private var stateLabel: some View {
    switch submodule.state {
    case .upToDate:
      Text(submodule.commit.shortened)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
    case .notInitialized:
      Text("Not Initialized")
        .font(.caption)
        .foregroundStyle(.tertiary)
    case .differentCommit:
      Text("Changed")
        .font(.caption)
        .foregroundStyle(.orange)
    case .conflicted:
      Text("Conflict")
        .font(.caption)
        .foregroundStyle(.red)
    }
  }

  private var stateDescription: String {
    switch submodule.state {
    case .upToDate: "Checked out at \(submodule.commit.shortened)"
    case .notInitialized: "Not initialized"
    case .differentCommit:
      "Checked out at \(submodule.commit.shortened), not the recorded commit"
    case .conflicted: "Conflicted"
    }
  }

  private var help: String {
    var lines = [stateDescription]
    if let describe = submodule.describe { lines.append(describe) }
    if let url = submodule.url { lines.append(url) }
    return lines.joined(separator: "\n")
  }
}

/// A destructive submodule action awaiting confirmation.
enum PendingSubmoduleAction {
  case deinitialize(Submodule)
  case remove(Submodule)

  var title: String {
    switch self {
    case .deinitialize(let submodule): "Deinitialize “\(submodule.path)”?"
    case .remove(let submodule): "Remove the submodule “\(submodule.path)”?"
    }
  }

  var actionTitle: String {
    switch self {
    case .deinitialize: "Deinitialize"
    case .remove: "Remove Submodule"
    }
  }

  var message: String {
    switch self {
    case .deinitialize:
      "Its folder is emptied and its local settings are forgotten. The submodule stays in the repository; Initialize and Update checks it out again. git refuses if the checkout has local changes, unless you discard them."
    case .remove:
      "Its folder, its .gitmodules entry, and its recorded commit are removed and the removal is staged; commit to finish. The cloned data stays in .git/modules. git refuses if the checkout has local changes, unless you discard them."
    }
  }
}

@MainActor
struct SubmoduleContextMenu: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  let submodule: Submodule
  let confirm: (PendingSubmoduleAction) -> Void
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    if submodule.state != .notInitialized {
      Button("Open in New Window") {
        openWindow(value: Repository(rootURL: model.workingDirectory(of: submodule)).id)
      }
      Divider()
    }
    Button(submodule.state == .notInitialized ? "Initialize and Update" : "Update") {
      Task { await model.updateSubmodules([submodule]) }
    }
    .disabled(model.isBusy)
    .help("Check out the commit the repository records, cloning it first if needed")
    Button("Sync URL") {
      Task { await model.syncSubmodules([submodule]) }
    }
    .disabled(model.isBusy)
    .help("Copy the URL from .gitmodules into the local configuration")
    Divider()
    Button("Reveal in Finder") {
      NSWorkspace.shared.activateFileViewerSelecting([model.workingDirectory(of: submodule)])
    }
    if let url = submodule.url {
      Button("Copy URL") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
      }
    }
    Divider()
    if submodule.state != .notInitialized {
      Button("Deinitialize…", role: .destructive) { confirm(.deinitialize(submodule)) }
        .disabled(model.isBusy)
        .help("Empty the checkout but keep the submodule in the repository")
    }
    Button("Remove Submodule…", role: .destructive) { confirm(.remove(submodule)) }
      .disabled(model.isBusy)
  }
}

/// Clones a repository into a folder of this one as a new submodule.
@MainActor
struct AddSubmoduleSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var url = ""
  @State private var path = ""
  /// Until the path is edited, it follows the URL's last component.
  @State private var pathIsEdited = false

  var body: some View {
    SheetFormLayout(
      title: "Add Submodule",
      subtitle: "The repository is cloned into the folder and staged as a submodule."
    ) {
      Form {
        TextField("URL", text: $url, prompt: Text("https://github.com/owner/repo.git"))
        TextField("Folder", text: pathBinding, prompt: Text("Vendor/repo"))
          .onSubmit(add)
      }
      .textFieldStyle(.roundedBorder)
      .frame(width: 420)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Add", action: add)
        .keyboardShortcut(.defaultAction)
        .disabled(!isValid)
    }
  }

  private var pathBinding: Binding<String> {
    Binding(
      get: { pathIsEdited ? path : Self.suggestedPath(for: url) },
      set: {
        path = $0
        pathIsEdited = true
      }
    )
  }

  private var trimmedURL: String { url.trimmingCharacters(in: .whitespaces) }

  private var trimmedPath: String {
    pathBinding.wrappedValue.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
  }

  private var isValid: Bool {
    !trimmedURL.isEmpty && !trimmedPath.isEmpty
      && !model.submodules.contains { $0.path == trimmedPath }
  }

  /// `https://host/owner/Kit.git` → `Kit`.
  static func suggestedPath(for url: String) -> String {
    let trimmed = url.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
    let last = trimmed.split(whereSeparator: { $0 == "/" || $0 == ":" }).last ?? ""
    return last.hasSuffix(".git") ? String(last.dropLast(4)) : String(last)
  }

  private func add() {
    guard isValid else { return }
    let url = trimmedURL
    let path = trimmedPath
    dismiss()
    Task { await model.addSubmodule(url: url, path: path) }
  }
}
