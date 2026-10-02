import Foundation

/// A `git archive` output format, chosen from the file name it's saved as.
public enum ArchiveFormat: String, Sendable, Hashable, CaseIterable {
  case zip
  case tarGz = "tar.gz"
  case tar

  /// The format a file name asks for: `.tar.gz` or `.tgz`, `.tar`, and
  /// otherwise zip.
  public init(fileName: String) {
    let name = fileName.lowercased()
    if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
      self = .tarGz
    } else if name.hasSuffix(".tar") {
      self = .tar
    } else {
      self = .zip
    }
  }
}
