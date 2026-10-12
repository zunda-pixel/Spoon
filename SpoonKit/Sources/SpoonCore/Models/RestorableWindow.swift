public import MemberwiseInit

/// A repository window to reopen at launch.
@MemberwiseInit(.public)
public struct RestorableWindow: Sendable, Hashable, Codable {
  /// The repository shown in each tab, in tab order.
  public var tabs: [Repository.ID]
  /// `NSWindow.frameDescriptor`, so the window reopens where it was.
  public var frame: String? = nil
}
