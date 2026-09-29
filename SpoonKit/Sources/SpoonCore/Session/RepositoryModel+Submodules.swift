public import Foundation

extension RepositoryModel {
  /// Initializes and checks out `submodules`, or all of them when empty.
  public func updateSubmodules(_ submodules: [Submodule] = []) async {
    await perform { try await $0.updateSubmodules(paths: submodules.map(\.path)) }
  }

  /// Copies each submodule's URL from `.gitmodules` into the local config.
  public func syncSubmodules(_ submodules: [Submodule] = []) async {
    await perform { try await $0.syncSubmodules(paths: submodules.map(\.path)) }
  }

  @discardableResult
  public func addSubmodule(url: String, path: String) async -> Bool {
    await perform { try await $0.addSubmodule(url: url, path: path) }
  }

  /// The submodule's own checkout, once initialized.
  public func workingDirectory(of submodule: Submodule) -> URL {
    repository.rootURL.appending(path: submodule.path, directoryHint: .isDirectory)
  }
}
