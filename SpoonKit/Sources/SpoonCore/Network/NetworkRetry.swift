import Foundation
import os
public import Retry

/// Retrying for Spoon's own HTTP requests, which are all safe to send again:
/// GitHub GraphQL queries and release lookups and downloads.
public enum NetworkRetry {
  /// Three attempts with exponential backoff and jitter (about one second,
  /// then two), for dropped connections, timeouts, and 5xx responses. Sign-in
  /// and rate-limit failures are reported at once.
  public static func configuration(
    backoff: Backoff<ContinuousClock> = .default(baseDelay: .seconds(1), maxDelay: .seconds(8))
  ) -> RetryConfiguration<ContinuousClock> {
    RetryConfiguration(
      maxAttempts: 3,
      backoff: backoff,
      appleLogger: Logger(subsystem: "com.spoon.app", category: "network"),
      recoverFromFailure: { isTransient($0) ? .retry : .throw }
    )
  }

  /// Whether another attempt could succeed without anything changing on
  /// this side.
  static func isTransient(_ error: any Error) -> Bool {
    switch error {
    case let error as URLError:
      [
        .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
        .dnsLookupFailed, .notConnectedToInternet,
      ].contains(error.code)
    case let error as GitHubError:
      if case .http(let status) = error.kind { isTransientStatus(status) } else { false }
    case let error as GitHubReleaseFeed.FeedError:
      if case .unexpectedStatus(let status) = error { isTransientStatus(status) } else { false }
    default:
      false
    }
  }

  /// Server errors and gateway failures; 501 means the request itself is
  /// unsupported.
  static func isTransientStatus(_ status: Int) -> Bool {
    [500, 502, 503, 504].contains(status)
  }
}
