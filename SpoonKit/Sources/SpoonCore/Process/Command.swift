public import Foundation

/// A fully resolved subprocess invocation.
///
/// `executable` must be an absolute path — resolving bare tool names is
/// `ToolLocator`'s job. Keeping resolution out of `Command` means every
/// invocation can be logged, replayed, and asserted on byte-for-byte in tests.
public struct Command: Sendable, Hashable {
  public var executable: URL
  public var arguments: [String]
  public var workingDirectory: URL?
  /// Variables applied on top of (or instead of) the parent process environment.
  public var environment: [String: String]
  /// When false the child sees only `environment` — used for hermetic AI runs.
  public var inheritsEnvironment: Bool
  public var standardInput: Data?
  /// `nil` disables the timeout (long-running agent sessions).
  public var timeout: Duration?

  public init(
    executable: URL,
    arguments: [String] = [],
    workingDirectory: URL? = nil,
    environment: [String: String] = [:],
    inheritsEnvironment: Bool = true,
    standardInput: Data? = nil,
    timeout: Duration? = .seconds(60)
  ) {
    self.executable = executable
    self.arguments = arguments
    self.workingDirectory = workingDirectory
    self.environment = environment
    self.inheritsEnvironment = inheritsEnvironment
    self.standardInput = standardInput
    self.timeout = timeout
  }

  /// The environment the child process will actually receive.
  public var resolvedEnvironment: [String: String] {
    guard inheritsEnvironment else { return environment }
    return ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
  }

  /// Rendering for logs and error messages; not shell-escaped.
  public var displayString: String {
    ([executable.lastPathComponent] + arguments).joined(separator: " ")
  }
}

public struct CommandResult: Sendable {
  public var exitCode: Int32
  public var standardOutput: Data
  public var standardError: Data

  public init(exitCode: Int32, standardOutput: Data, standardError: Data) {
    self.exitCode = exitCode
    self.standardOutput = standardOutput
    self.standardError = standardError
  }

  public var isSuccess: Bool { exitCode == 0 }

  public var standardOutputText: String {
    String(decoding: standardOutput, as: UTF8.self)
  }

  public var standardErrorText: String {
    String(decoding: standardError, as: UTF8.self)
  }

  /// Throws `CommandError.nonZeroExit` on failure. `run(_:)` itself never
  /// throws for non-zero exits because several git commands use them
  /// meaningfully; callers opt in per call site.
  @discardableResult
  public func checkSuccess(of command: Command) throws -> CommandResult {
    guard isSuccess else {
      throw CommandError(
        kind: .nonZeroExit,
        command: command,
        exitCode: exitCode,
        standardErrorExcerpt: CommandError.excerpt(from: standardError)
      )
    }
    return self
  }
}

public enum CommandEvent: Sendable {
  case standardOutput(Data)
  case standardError(Data)
  case exited(Int32)
}

public struct CommandError: Error, Sendable {
  public enum Kind: Sendable, Equatable {
    case launchFailed(reason: String)
    case nonZeroExit
    case terminatedBySignal(Int32)
    case timedOut
  }

  public var kind: Kind
  public var command: Command
  public var exitCode: Int32?
  public var standardErrorExcerpt: String

  public init(kind: Kind, command: Command, exitCode: Int32? = nil, standardErrorExcerpt: String = "") {
    self.kind = kind
    self.command = command
    self.exitCode = exitCode
    self.standardErrorExcerpt = standardErrorExcerpt
  }

  /// Last few lines of stderr — the part users need to see in error alerts.
  public static func excerpt(from stderr: Data, maxLines: Int = 8, maxBytes: Int = 2048) -> String {
    let tail = stderr.suffix(maxBytes)
    let text = String(decoding: tail, as: UTF8.self)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    return lines.suffix(maxLines).joined(separator: "\n")
  }
}

extension CommandError: LocalizedError {
  public var errorDescription: String? {
    let name = command.executable.lastPathComponent
    switch kind {
    case .launchFailed(let reason):
      return "Could not launch \(name): \(reason)"
    case .nonZeroExit:
      let code = exitCode.map(String.init) ?? "?"
      let detail = standardErrorExcerpt.isEmpty ? "" : "\n\(standardErrorExcerpt)"
      return "\(name) exited with code \(code)\(detail)"
    case .terminatedBySignal(let signal):
      return "\(name) was terminated by signal \(signal)"
    case .timedOut:
      return "\(name) timed out"
    }
  }
}
