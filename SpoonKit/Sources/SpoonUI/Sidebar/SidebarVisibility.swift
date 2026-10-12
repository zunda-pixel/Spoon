import SwiftUI

/// `@AppStorage` keys for Workspace sidebar rows the user can hide.
enum SidebarVisibilityKey {
  static let showsReflog = "sidebar.showsReflog"
  static let showsPullRequests = "sidebar.showsPullRequests"
}

/// Toggles for the optional Workspace rows, shared by the View menu and the
/// sidebar's context menu.
@MainActor
struct SidebarVisibilityToggles: View {
  @AppStorage(SidebarVisibilityKey.showsReflog) private var showsReflog = true
  @AppStorage(SidebarVisibilityKey.showsPullRequests) private var showsPullRequests = true

  var body: some View {
    Toggle("Reflog", isOn: $showsReflog)
    Toggle("Pull Requests", isOn: $showsPullRequests)
  }
}
