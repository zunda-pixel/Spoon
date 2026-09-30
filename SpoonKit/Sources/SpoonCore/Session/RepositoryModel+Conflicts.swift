public import Foundation

extension RepositoryModel {
  public enum ConflictEditError: LocalizedError {
    case notText(path: String)
    case changedOnDisk(path: String)

    public var errorDescription: String? {
      switch self {
      case .notText(let path):
        "“\(path)” is not a UTF-8 text file, so its conflicts can’t be resolved here."
      case .changedOnDisk(let path):
        "“\(path)” changed since it was shown. Review its conflicts again."
      }
    }
  }

  /// The working-tree copy of a conflicted file, split at its conflict
  /// markers; `nil` when the file is missing (deleted on one side).
  public func conflictDocument(path: String) async throws -> ConflictDocument? {
    guard let text = try await readWorkingTreeText(path) else { return nil }
    return ConflictDocument(text: text)
  }

  /// Replaces one conflict region of `path` with `choice`, leaving the
  /// file's other conflicts alone. Refuses if the region no longer matches
  /// `block`, e.g. after an edit in another app.
  @discardableResult
  public func resolveConflictBlock(
    _ block: ConflictBlock,
    in path: String,
    using choice: ConflictChoice
  ) async -> Bool {
    isBusy = true
    var succeeded = false
    do {
      guard let text = try await readWorkingTreeText(path) else {
        throw ConflictEditError.changedOnDisk(path: path)
      }
      let document = ConflictDocument(text: text)
      guard document.blocks.first(where: { $0.index == block.index }) == block else {
        throw ConflictEditError.changedOnDisk(path: path)
      }
      let resolved = document.text(resolving: block.index, with: choice)
      let url = repository.rootURL.appending(path: path)
      // Not atomic: an atomic write replaces the file and drops its
      // permissions, such as the executable bit.
      try await Task.detached { try Data(resolved.utf8).write(to: url) }.value
      clearError()
      succeeded = true
    } catch {
      lastErrorMessage = error.localizedDescription
      lastErrorIsFromBackgroundRead = false
    }
    isBusy = false
    await refresh()
    return succeeded
  }

  /// Drops rerere's recorded resolution for `path` and puts its conflict
  /// markers back, so it can be resolved (and recorded) again.
  public func forgetRecordedResolution(path: String) async {
    await perform {
      try await $0.forgetRecordedResolution(path: path)
      try await $0.restoreConflictMarkers(path: path)
    }
  }

  /// Deletes every resolution rerere has recorded in this repository.
  public func forgetAllRecordedResolutions() async {
    await perform { try await $0.forgetAllRecordedResolutions() }
  }

  /// Puts every conflict marker of `path` back, discarding resolutions
  /// made so far.
  public func restoreConflictMarkers(path: String) async {
    await perform { try await $0.restoreConflictMarkers(path: path) }
  }

  private func readWorkingTreeText(_ path: String) async throws -> String? {
    let url = repository.rootURL.appending(path: path)
    let data = try await Task.detached { () throws -> Data? in
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      return try Data(contentsOf: url)
    }.value
    guard let data else { return nil }
    guard let text = String(data: data, encoding: .utf8) else {
      throw ConflictEditError.notText(path: path)
    }
    return text
  }
}
