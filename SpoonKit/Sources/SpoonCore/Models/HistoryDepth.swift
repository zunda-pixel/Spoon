public import Foundation

/// How much more history a shallow clone fetches.
public enum HistoryDepth: Sendable, Hashable {
  /// This many more commits behind the current boundary (`--deepen`).
  case commits(Int)
  /// Every commit made on or after the date (`--shallow-since`).
  case since(Date)
  /// All of it, ending the shallow clone (`--unshallow`).
  case full

  var arguments: [String] {
    switch self {
    case .commits(let count): ["--deepen=\(max(1, count))"]
    case .since(let date):
      ["--shallow-since=\(date.formatted(.iso8601.year().month().day()))"]
    case .full: ["--unshallow"]
    }
  }
}
