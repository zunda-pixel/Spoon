/// What `git backfill` would download, measured before running it.
public struct BackfillEstimate: Sendable, Hashable {
  /// Objects reachable from HEAD that are not present locally.
  public var missingObjectCount: Int
  /// Total bytes the promisor remote reports for them; `nil` when the
  /// remote cannot report sizes.
  public var downloadByteCount: Int?
  /// Why `downloadByteCount` is unavailable, for display.
  public var sizeUnavailableReason: String?

  public init(missingObjectCount: Int, downloadByteCount: Int?, sizeUnavailableReason: String?) {
    self.missingObjectCount = missingObjectCount
    self.downloadByteCount = downloadByteCount
    self.sizeUnavailableReason = sizeUnavailableReason
  }
}
