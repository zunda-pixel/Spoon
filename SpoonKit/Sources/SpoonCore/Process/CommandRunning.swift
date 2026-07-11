/// The single seam through which Spoon launches external processes —
/// git, gh, claude, and codex all go through this. Fakes implement it
/// to replay recorded transcripts in tests.
public protocol CommandRunning: Sendable {
  /// Runs to completion and buffers output. Does NOT throw on non-zero exit
  /// (use `CommandResult.checkSuccess(of:)`); throws for launch failures,
  /// timeouts, signal termination, and cancellation.
  func run(_ command: Command) async throws -> CommandResult

  /// Streams output as it arrives. The stream finishes after `.exited`,
  /// or throws for launch failures, timeouts, and signal termination.
  /// Cancelling iteration terminates the child process.
  func events(_ command: Command) -> AsyncThrowingStream<CommandEvent, any Error>
}
