import Defaults
import Foundation
import Testing

@testable import SpoonCore

@Suite("App updates", .serialized)
struct AppUpdaterTests {
  @Test func versionsParseTagsAndCompareNumerically() {
    #expect(AppVersion("0.0.4") == AppVersion(0, 0, 4))
    #expect(AppVersion("v1.2") == AppVersion(1, 2, 0))
    #expect(AppVersion("0.0.10")! > AppVersion("0.0.9")!)
    #expect(AppVersion("") == nil)
    #expect(AppVersion("1.0-beta") == nil)
    #expect(AppVersion("1.2.3.4") == nil)
  }

  @Test func latestReleaseDecodesTagNotesAndMacArchive() throws {
    let json = """
      {"tag_name": "0.0.5", "html_url": "https://github.com/o/r/releases/tag/0.0.5",
       "body": "## What's new", "published_at": "2026-09-30T01:02:03Z",
       "assets": [
         {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
         {"name": "Spoon-0.0.5-macOS.zip", "browser_download_url": "https://example.com/a.zip"}
       ]}
      """
    let release = try AppRelease.decodeLatest(from: Data(json.utf8))

    #expect(release.version == AppVersion(0, 0, 5))
    #expect(release.archiveURL.absoluteString == "https://example.com/a.zip")
    #expect(release.notes == "## What's new")
    #expect(release.publishedAt != nil)

    let noArchive = #"{"tag_name": "0.0.6", "html_url": "https://x.y", "assets": []}"#
    #expect(throws: AppRelease.DecodingError.missingArchive(tag: "0.0.6")) {
      try AppRelease.decodeLatest(from: Data(noArchive.utf8))
    }
  }

  @MainActor
  @Test func launchChecksOfferOnlyNewerUnskippedReleases() async {
    Defaults[.skippedUpdateVersion] = nil
    Defaults[.automaticallyCheckForUpdates] = true
    defer { Defaults.reset(.skippedUpdateVersion, .automaticallyCheckForUpdates) }

    let current = makeUpdater(latest: "0.0.4", current: AppVersion(0, 0, 4))
    await current.checkAtLaunchIfNeeded()
    #expect(current.state == .idle)
    #expect(current.availableRelease == nil)

    let newer = makeUpdater(latest: "0.0.5", current: AppVersion(0, 0, 4))
    await newer.checkAtLaunchIfNeeded()
    #expect(newer.availableRelease?.tagName == "0.0.5")

    newer.skip(newer.availableRelease!)
    let afterSkip = makeUpdater(latest: "0.0.5", current: AppVersion(0, 0, 4))
    await afterSkip.checkAtLaunchIfNeeded()
    #expect(afterSkip.availableRelease == nil)
    // A manual check still offers the skipped version.
    await afterSkip.checkForUpdates()
    #expect(afterSkip.availableRelease?.tagName == "0.0.5")
  }

  @MainActor
  @Test func developmentBuildsAndFailuresStayQuietAtLaunch() async {
    Defaults[.automaticallyCheckForUpdates] = true
    defer { Defaults.reset(.automaticallyCheckForUpdates) }

    let development = makeUpdater(latest: "0.0.5", current: nil)
    await development.checkAtLaunchIfNeeded()
    #expect(development.state == .idle)

    let failing = makeUpdater(latest: nil, current: AppVersion(0, 0, 4))
    await failing.checkAtLaunchIfNeeded()
    #expect(failing.state == .idle)
    await failing.checkForUpdates()
    guard case .failed = failing.state else {
      Issue.record("A manual check should report the failure")
      return
    }

    let upToDate = makeUpdater(latest: "0.0.4", current: AppVersion(0, 0, 4))
    await upToDate.checkForUpdates()
    #expect(upToDate.state == .upToDate)
  }

  @Test func installerReplacesTheBundleAfterVerifyingIt() async throws {
    let root = URL.temporaryDirectory.appending(path: "spoon-update-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let installed = try makeApp(in: root.appending(path: "Applications"), version: "old")
    let release = try makeApp(in: root.appending(path: "release"), version: "new")
    let runner = SubprocessCommandRunner()
    try await run("/usr/bin/codesign", ["--force", "--sign", "-", release.path], runner)
    let archive = root.appending(path: "Spoon-macOS.zip")
    try await run(
      "/usr/bin/ditto", ["-c", "-k", "--keepParent", release.path, archive.path], runner)

    await #expect(throws: AppUpdateInstaller.InstallError.self) {
      try await AppUpdateInstaller(runner: runner).install(
        archive: archive, replacing: installed, bundleIdentifier: "com.example.other")
    }
    try await run(
      "/usr/bin/ditto", ["-c", "-k", "--keepParent", release.path, archive.path], runner)
    try await AppUpdateInstaller(runner: runner).install(
      archive: archive, replacing: installed, bundleIdentifier: "com.spoon.tests")

    let marker = try String(
      contentsOf: installed.appending(path: "Contents/Resources/version.txt"), encoding: .utf8)
    #expect(marker == "new")
    let leftovers = try FileManager.default.contentsOfDirectory(
      atPath: installed.deletingLastPathComponent().path)
    #expect(leftovers == ["Spoon.app"])
  }

  @Test func translocatedAppsAreRejected() {
    let translocated = URL(filePath: "/private/var/folders/x/AppTranslocation/ABC/d/Spoon.app")
    #expect(throws: AppUpdateInstaller.InstallError.translocated) {
      try AppUpdateInstaller.validateInstallLocation(translocated)
    }
  }

  // MARK: - Helpers

  @MainActor
  private func makeUpdater(latest: String?, current: AppVersion?) -> AppUpdater {
    AppUpdater(
      feed: StubReleaseFeed(tag: latest),
      installer: AppUpdateInstaller(),
      bundleURL: URL(filePath: "/Applications/Spoon.app"),
      bundleIdentifier: "com.spoon.app",
      currentVersion: current
    )
  }

  private func makeApp(in directory: URL, version: String) throws -> URL {
    let app = directory.appending(path: "Spoon.app")
    let contents = app.appending(path: "Contents")
    try FileManager.default.createDirectory(
      at: contents.appending(path: "Resources"), withIntermediateDirectories: true)
    let plist: [String: Any] = [
      "CFBundleIdentifier": "com.spoon.tests",
      "CFBundleName": "Spoon",
      "CFBundlePackageType": "APPL",
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appending(path: "Info.plist"))
    try Data(version.utf8).write(to: contents.appending(path: "Resources/version.txt"))
    return app
  }

  private func run(_ tool: String, _ arguments: [String], _ runner: SubprocessCommandRunner)
    async throws
  {
    let command = Command(executable: URL(filePath: tool), arguments: arguments)
    _ = try await runner.run(command).checkSuccess(of: command)
  }
}

private struct StubReleaseFeed: ReleaseFeed {
  let tag: String?

  struct Offline: Error {}

  func latestRelease() async throws -> AppRelease {
    guard let tag, let version = AppVersion(tag) else { throw Offline() }
    return AppRelease(
      version: version,
      tagName: tag,
      pageURL: URL(string: "https://example.com/\(tag)")!,
      archiveURL: URL(string: "https://example.com/\(tag).zip")!,
      notes: "",
      publishedAt: nil
    )
  }

  func downloadArchive(of release: AppRelease) async throws -> URL { throw Offline() }
}
