import Defaults
public import Foundation
public import Observation

/// Checks GitHub for a newer Spoon release and installs it.
@MainActor
@Observable
public final class AppUpdater {
  public enum State: Sendable, Hashable {
    case idle
    case checking
    case upToDate
    case available(AppRelease)
    case installing(AppRelease)
    /// Installed; relaunch to finish.
    case readyToRelaunch(AppRelease)
    case failed(String)
  }

  public private(set) var state = State.idle
  /// The release waiting to be installed, until it is skipped or installed.
  public private(set) var availableRelease: AppRelease?
  /// The running build's version; `nil` for development builds, which are
  /// never offered updates automatically.
  public let currentVersion: AppVersion?

  private let feed: any ReleaseFeed
  private let installer: AppUpdateInstaller
  private let bundleURL: URL
  private let bundleIdentifier: String
  private var hasCheckedAtLaunch = false

  public init(
    feed: any ReleaseFeed = GitHubReleaseFeed(),
    installer: AppUpdateInstaller = AppUpdateInstaller(),
    bundle: Bundle = .main
  ) {
    self.feed = feed
    self.installer = installer
    self.bundleURL = bundle.bundleURL
    self.bundleIdentifier = bundle.bundleIdentifier ?? "com.spoon.app"
    // Release builds record their tag; plain Xcode builds leave it empty.
    let tag = bundle.object(forInfoDictionaryKey: "SpoonReleaseTag") as? String
    self.currentVersion = tag.flatMap(AppVersion.init)
  }

  init(
    feed: any ReleaseFeed,
    installer: AppUpdateInstaller,
    bundleURL: URL,
    bundleIdentifier: String,
    currentVersion: AppVersion?
  ) {
    self.feed = feed
    self.installer = installer
    self.bundleURL = bundleURL
    self.bundleIdentifier = bundleIdentifier
    self.currentVersion = currentVersion
  }

  public var automaticallyChecks: Bool {
    get { Defaults[.automaticallyCheckForUpdates] }
    set { Defaults[.automaticallyCheckForUpdates] = newValue }
  }

  /// The launch-time check: once per process, release builds only, and a
  /// version the user skipped is not offered again.
  public func checkAtLaunchIfNeeded() async {
    guard !hasCheckedAtLaunch, automaticallyChecks, currentVersion != nil else { return }
    hasCheckedAtLaunch = true
    await check(userInitiated: false)
  }

  /// "Check for Updates…": reports the result even when there is nothing new.
  public func checkForUpdates() async {
    await check(userInitiated: true)
  }

  private func check(userInitiated: Bool) async {
    switch state {
    case .checking, .installing, .readyToRelaunch: return
    default: break
    }
    state = .checking
    do {
      let release = try await feed.latestRelease()
      let isNewer = currentVersion.map { release.version > $0 } ?? userInitiated
      let isSkipped = !userInitiated && Defaults[.skippedUpdateVersion] == release.tagName
      if isNewer, !isSkipped {
        availableRelease = release
        state = .available(release)
      } else {
        state = userInitiated ? .upToDate : .idle
      }
    } catch {
      // A failed background check stays quiet; only a manual one reports it.
      state = userInitiated ? .failed(error.localizedDescription) : .idle
    }
  }

  /// Stops offering `release` automatically until a newer one appears.
  public func skip(_ release: AppRelease) {
    Defaults[.skippedUpdateVersion] = release.tagName
    availableRelease = nil
    state = .idle
  }

  public func dismiss() {
    if case .available = state { state = .idle }
    if case .upToDate = state { state = .idle }
    if case .failed = state { state = .idle }
  }

  /// Downloads `release` and replaces the app bundle on disk.
  public func install(_ release: AppRelease) async {
    state = .installing(release)
    do {
      try AppUpdateInstaller.validateInstallLocation(bundleURL)
      let archive = try await feed.downloadArchive(of: release)
      try await installer.install(
        archive: archive,
        replacing: bundleURL,
        bundleIdentifier: bundleIdentifier
      )
      availableRelease = nil
      state = .readyToRelaunch(release)
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  /// The bundle to reopen after installing.
  public var appURL: URL { bundleURL }
}
