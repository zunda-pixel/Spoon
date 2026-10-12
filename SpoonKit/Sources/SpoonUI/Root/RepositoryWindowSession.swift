import AppKit
import SpoonCore
import SwiftUI

/// Saves the open repository windows and their tabs when the app quits, and
/// puts reopened windows back into their tabs and frames.
///
/// The app does this itself, rather than through SwiftUI's state
/// restoration, so the windows come back even when macOS is set to close
/// windows when quitting an app.
@MainActor
final class RepositoryWindowSession {
  static let shared = RepositoryWindowSession()

  private struct Entry {
    weak var window: NSWindow?
    var repositoryID: Repository.ID?
  }

  private var entries: [ObjectIdentifier: Entry] = [:]
  /// Restored windows still waiting for all of their tabs to appear.
  private var pending: [RestorableWindow] = []
  private weak var appModel: AppModel?
  private var terminationObserver: (any NSObjectProtocol)?

  private init() {}

  /// Starts saving the windows at quit; later calls do nothing.
  func start(appModel: AppModel) {
    guard terminationObserver == nil else { return }
    self.appModel = appModel
    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated {
        let session = RepositoryWindowSession.shared
        session.appModel?.saveOpenWindows(session.openWindows())
      }
    }
  }

  /// Records which repository `window` shows (`nil` for Welcome).
  func update(window: NSWindow, repositoryID: Repository.ID?) {
    entries = entries.filter { $0.value.window != nil }
    entries[ObjectIdentifier(window)] = Entry(window: window, repositoryID: repositoryID)
    arrangeRestoredWindows()
  }

  /// Regroups and places these windows as their tabs open.
  func expect(_ windows: [RestorableWindow]) {
    pending = windows
    arrangeRestoredWindows()
  }

  /// Open repository windows, back to front, each with its tabs in order.
  private func openWindows() -> [RestorableWindow] {
    var visited: Set<ObjectIdentifier> = []
    var result: [RestorableWindow] = []
    for window in NSApp.orderedWindows.reversed()
    where window.isVisible || window.isMiniaturized {
      let tabs = window.tabGroup?.windows ?? [window]
      guard !tabs.contains(where: { visited.contains(ObjectIdentifier($0)) }) else { continue }
      visited.formUnion(tabs.map(ObjectIdentifier.init))
      let ids = tabs.compactMap { entries[ObjectIdentifier($0)]?.repositoryID }
      guard !ids.isEmpty else { continue }
      let selected = window.tabGroup?.selectedWindow ?? window
      result.append(RestorableWindow(tabs: ids, frame: selected.frameDescriptor))
    }
    return result
  }

  private func window(showing repositoryID: Repository.ID) -> NSWindow? {
    entries.values.first { $0.repositoryID == repositoryID && $0.window != nil }?.window
  }

  private func arrangeRestoredWindows() {
    pending.removeAll { restorable in
      let windows = restorable.tabs.compactMap(window(showing:))
      guard windows.count == restorable.tabs.count, let first = windows.first else {
        return false
      }
      if let frame = restorable.frame {
        first.setFrame(from: frame)
      }
      for (previous, next) in zip(windows, windows.dropFirst())
      where previous.tabGroup?.windows.contains(next) != true {
        previous.addTabbedWindow(next, ordered: .above)
      }
      return true
    }
  }
}

/// Reports the `NSWindow` hosting a SwiftUI view.
struct WindowReader: NSViewRepresentable {
  let onWindow: (NSWindow) -> Void

  func makeNSView(context: Context) -> WindowReportingView {
    WindowReportingView(onWindow: onWindow)
  }

  func updateNSView(_ view: WindowReportingView, context: Context) {
    view.onWindow = onWindow
    // NSView.window is unowned(unsafe); AppKit keeps it valid while attached.
    if let window = unsafe view.window {
      onWindow(window)
    }
  }

  final class WindowReportingView: NSView {
    var onWindow: (NSWindow) -> Void

    init(onWindow: @escaping (NSWindow) -> Void) {
      self.onWindow = onWindow
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let window = unsafe window {
        onWindow(window)
      }
    }
  }
}
