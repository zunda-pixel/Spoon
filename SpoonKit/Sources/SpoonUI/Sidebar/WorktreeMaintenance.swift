import AppKit
import SpoonCore
import SwiftUI

/// Lock, unlock, and move actions for a linked worktree's context menu.
@MainActor
struct WorktreeMaintenanceMenuItems: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  let worktree: Worktree

  var body: some View {
    if !worktree.isMain {
      if worktree.isLocked {
        Button("Unlock Worktree") {
          Task { await model.unlockWorktree(worktree) }
        }
        .disabled(model.isBusy)
      } else {
        Button("Lock Worktree…") {
          navigation.present(.lockWorktree(worktree))
        }
        .disabled(model.isBusy)
        .help("Keep git from pruning, moving, or removing this worktree")
      }
      Button("Move Worktree…") {
        chooseDestination()
      }
      .disabled(model.isBusy || worktree.isLocked || worktree.isPrunable)
    }
  }

  private func chooseDestination() {
    let panel = NSSavePanel()
    panel.title = "Move Worktree"
    panel.prompt = "Move"
    panel.message = "Choose the new folder for the “\(worktree.name)” worktree."
    panel.directoryURL = worktree.path.deletingLastPathComponent()
    panel.nameFieldStringValue = worktree.name
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    Task { await model.moveWorktree(worktree, to: destination) }
  }
}

/// Asks for an optional reason and locks a linked worktree.
@MainActor
struct LockWorktreeSheet: View {
  let model: RepositoryModel
  let worktree: Worktree
  @Environment(\.dismiss) private var dismiss
  @State private var reason = ""

  var body: some View {
    SheetFormLayout(title: "Lock Worktree “\(worktree.name)”") {
      Text(
        "A locked worktree is kept even if its folder is on a removable or network drive that is not connected, and it can’t be moved or deleted until it is unlocked."
      )
      .frame(width: 400, alignment: .leading)
      TextField("Reason", text: $reason, prompt: Text("Optional, e.g. “on external drive”"))
        .textFieldStyle(.roundedBorder)
        .frame(width: 400)
        .onSubmit(lock)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Lock", action: lock)
        .keyboardShortcut(.defaultAction)
        .disabled(model.isBusy)
    }
  }

  private func lock() {
    let reason = reason
    dismiss()
    Task { await model.lockWorktree(worktree, reason: reason) }
  }
}
