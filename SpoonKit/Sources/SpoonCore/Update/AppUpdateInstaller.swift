public import Foundation

/// Unpacks a downloaded release and swaps it in for the running app bundle.
public struct AppUpdateInstaller: Sendable {
  public enum InstallError: LocalizedError, Sendable, Hashable {
    case translocated
    case notWritable(URL)
    case appNotFoundInArchive
    case bundleIdentifierMismatch(expected: String, found: String?)

    public var errorDescription: String? {
      switch self {
      case .translocated:
        "Spoon is running from a temporary location. Move Spoon to the Applications folder, open it from there, and try again."
      case .notWritable(let url):
        "Spoon can’t replace itself at \(url.deletingLastPathComponent().path(percentEncoded: false)). Move Spoon to a folder you can write to, such as Applications."
      case .appNotFoundInArchive:
        "The downloaded update does not contain Spoon.app."
      case .bundleIdentifierMismatch(let expected, let found):
        "The downloaded app is “\(found ?? "unknown")”, not \(expected)."
      }
    }
  }

  private let runner: any CommandRunning

  public init(runner: any CommandRunning = SubprocessCommandRunner()) {
    self.runner = runner
  }

  /// Checks the running bundle can be replaced before anything is downloaded.
  public static func validateInstallLocation(_ appURL: URL) throws {
    // Gatekeeper runs quarantined apps from a read-only randomized copy.
    if appURL.path(percentEncoded: false).contains("/AppTranslocation/") {
      throw InstallError.translocated
    }
    let parent = appURL.deletingLastPathComponent()
    guard FileManager.default.isWritableFile(atPath: parent.path(percentEncoded: false)) else {
      throw InstallError.notWritable(appURL)
    }
  }

  /// Replaces `appURL` with the app inside `archive`, after checking the new
  /// bundle has the same identifier and a valid code signature. The running
  /// process keeps working from memory until it relaunches.
  public func install(archive: URL, replacing appURL: URL, bundleIdentifier: String) async throws {
    try Self.validateInstallLocation(appURL)
    let fileManager = FileManager.default
    // Stage beside the destination so the final swap stays on one volume.
    let staging = appURL.deletingLastPathComponent()
      .appending(path: ".spoon-update-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    defer {
      try? fileManager.removeItem(at: staging)
      try? fileManager.removeItem(at: archive)
    }

    try await run("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
    guard let newApp = try Self.findApp(in: staging) else {
      throw InstallError.appNotFoundInArchive
    }
    let foundIdentifier = Bundle(url: newApp)?.bundleIdentifier
    guard foundIdentifier == bundleIdentifier else {
      throw InstallError.bundleIdentifierMismatch(
        expected: bundleIdentifier, found: foundIdentifier)
    }
    try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])

    _ = try fileManager.replaceItemAt(appURL, withItemAt: newApp)
  }

  static func findApp(in directory: URL) throws -> URL? {
    try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    ).first { $0.pathExtension == "app" }
  }

  private func run(_ executable: String, _ arguments: [String]) async throws {
    let command = Command(
      executable: URL(filePath: executable),
      arguments: arguments,
      timeout: .seconds(300)
    )
    _ = try await runner.run(command).checkSuccess(of: command)
  }
}
