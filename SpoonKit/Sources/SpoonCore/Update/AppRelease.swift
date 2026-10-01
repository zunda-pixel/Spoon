public import Foundation
public import MemberwiseInit

/// A `major.minor.patch` app version, parsed from a release tag such as
/// `0.0.4` or `v1.2.0`.
@MemberwiseInit(.public)
public struct AppVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
  @Init(label: "_")
  public var major: Int
  @Init(label: "_")
  public var minor: Int
  @Init(label: "_")
  public var patch: Int = 0

  /// `nil` unless the string is 1–3 dot-separated integers, optionally after `v`.
  public init?(_ string: String) {
    var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...3).contains(parts.count) else { return nil }
    let numbers = parts.compactMap { Int($0) }
    guard numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
    self.init(numbers[0], numbers.count > 1 ? numbers[1] : 0, numbers.count > 2 ? numbers[2] : 0)
  }

  public var description: String { "\(major).\(minor).\(patch)" }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
  }
}

/// A published Spoon release on GitHub.
@MemberwiseInit(.public)
public struct AppRelease: Sendable, Hashable, Identifiable {
  public var version: AppVersion
  public var tagName: String
  public var pageURL: URL
  /// The zipped `Spoon.app` attached to the release.
  public var archiveURL: URL
  public var notes: String
  public var publishedAt: Date?

  public var id: String { tagName }

  /// Why a GitHub release cannot be offered as an update.
  public enum DecodingError: LocalizedError, Sendable, Hashable {
    case unversionedTag(String)
    case missingArchive(tag: String)

    public var errorDescription: String? {
      switch self {
      case .unversionedTag(let tag):
        "The latest release “\(tag)” does not have a version number."
      case .missingArchive(let tag):
        "The latest release “\(tag)” has no macOS download."
      }
    }
  }

  /// Decodes `GET /repos/{owner}/{repo}/releases/latest`. The archive is the
  /// asset named `*-macOS.zip`, as published by the release workflow.
  public static func decodeLatest(from data: Data) throws -> AppRelease {
    struct Response: Decodable {
      struct Asset: Decodable {
        var name: String
        var browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
          case name
          case browserDownloadURL = "browser_download_url"
        }
      }

      var tagName: String
      var htmlURL: URL
      var body: String?
      var publishedAt: Date?
      var assets: [Asset]

      enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case publishedAt = "published_at"
        case assets
      }
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let response = try decoder.decode(Response.self, from: data)
    guard let version = AppVersion(response.tagName) else {
      throw DecodingError.unversionedTag(response.tagName)
    }
    guard let archive = response.assets.first(where: { $0.name.hasSuffix("-macOS.zip") }) else {
      throw DecodingError.missingArchive(tag: response.tagName)
    }
    return AppRelease(
      version: version,
      tagName: response.tagName,
      pageURL: response.htmlURL,
      archiveURL: archive.browserDownloadURL,
      notes: response.body ?? "",
      publishedAt: response.publishedAt
    )
  }
}
