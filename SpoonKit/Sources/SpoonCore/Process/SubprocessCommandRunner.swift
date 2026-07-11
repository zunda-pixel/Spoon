import Foundation
import Subprocess
import System

/// Production `CommandRunning` backed by swift-subprocess.
///
/// This file is the only place that touches the Subprocess package and the
/// only place in the Process layer allowed to use unsafe constructs (the
/// buffer-to-Data copy). If the pre-1.0 package breaks, a Foundation.Process
/// implementation of `CommandRunning` is a drop-in replacement.
public struct SubprocessCommandRunner: CommandRunning {
  /// Buffered `run(_:)` output cap; streaming has no cap.
  private static let outputLimit = 32 * 1024 * 1024

  public init() {}

  public func run(_ command: Command) async throws -> CommandResult {
    try await withTimeout(of: command) {
      try await execute(command)
    }
  }

  public func events(_ command: Command) -> AsyncThrowingStream<CommandEvent, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let exitCode = try await withTimeout(of: command) {
            try await stream(command, into: continuation)
          }
          continuation.yield(.exited(exitCode))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  // MARK: - Execution

  private func execute(_ command: Command) async throws -> CommandResult {
    let result: ExecutionResult<Void, DataOutput, DataOutput>
    do {
      if let stdin = command.standardInput {
        result = try await Subprocess.run(
          .path(FilePath(command.executable.path(percentEncoded: false))),
          arguments: Arguments(command.arguments),
          environment: subprocessEnvironment(for: command),
          workingDirectory: command.workingDirectory.map { FilePath($0.path(percentEncoded: false)) },
          platformOptions: platformOptions(),
          // .array, not .data: DataInput escapes Data's inline storage
          // pointer (upstream FIXME) and corrupts short payloads.
          input: .array(Array(stdin)),
          output: .data(limit: Self.outputLimit),
          error: .data(limit: Self.outputLimit)
        )
      } else {
        result = try await Subprocess.run(
          .path(FilePath(command.executable.path(percentEncoded: false))),
          arguments: Arguments(command.arguments),
          environment: subprocessEnvironment(for: command),
          workingDirectory: command.workingDirectory.map { FilePath($0.path(percentEncoded: false)) },
          platformOptions: platformOptions(),
          input: .none,
          output: .data(limit: Self.outputLimit),
          error: .data(limit: Self.outputLimit)
        )
      }
    } catch let error as CommandError {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw CommandError(kind: .launchFailed(reason: "\(error)"), command: command)
    }

    switch result.terminationStatus {
    case .exited(let code):
      return CommandResult(
        exitCode: Int32(code),
        standardOutput: result.standardOutput,
        standardError: result.standardError
      )
    case .signaled(let signal):
      throw CommandError(
        kind: .terminatedBySignal(Int32(signal)),
        command: command,
        standardErrorExcerpt: CommandError.excerpt(from: result.standardError)
      )
    }
  }

  /// Runs with `.sequence` output and pumps both pipes concurrently —
  /// draining stdout and stderr together is mandatory (codex writes verbose
  /// progress to stderr and will deadlock a naive single-pipe reader).
  private func stream(
    _ command: Command,
    into continuation: AsyncThrowingStream<CommandEvent, any Error>.Continuation
  ) async throws -> Int32 {
    let result: ExecutionResult<Void, SequenceOutput, SequenceOutput>
    do {
      if let stdin = command.standardInput {
        result = try await Subprocess.run(
          .path(FilePath(command.executable.path(percentEncoded: false))),
          arguments: Arguments(command.arguments),
          environment: subprocessEnvironment(for: command),
          workingDirectory: command.workingDirectory.map { FilePath($0.path(percentEncoded: false)) },
          platformOptions: platformOptions(),
          input: .array(Array(stdin)),
          output: .sequence,
          error: .sequence
        ) { execution in
          try await pump(execution, into: continuation)
        }
      } else {
        result = try await Subprocess.run(
          .path(FilePath(command.executable.path(percentEncoded: false))),
          arguments: Arguments(command.arguments),
          environment: subprocessEnvironment(for: command),
          workingDirectory: command.workingDirectory.map { FilePath($0.path(percentEncoded: false)) },
          platformOptions: platformOptions(),
          input: .none,
          output: .sequence,
          error: .sequence
        ) { execution in
          try await pump(execution, into: continuation)
        }
      }
    } catch let error as CommandError {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw CommandError(kind: .launchFailed(reason: "\(error)"), command: command)
    }

    switch result.terminationStatus {
    case .exited(let code):
      return Int32(code)
    case .signaled(let signal):
      throw CommandError(kind: .terminatedBySignal(Int32(signal)), command: command)
    }
  }

  private func pump<Input: InputProtocol>(
    _ execution: Execution<Input, SequenceOutput, SequenceOutput>,
    into continuation: AsyncThrowingStream<CommandEvent, any Error>.Continuation
  ) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        for try await buffer in execution.standardOutput {
          continuation.yield(.standardOutput(buffer.dataValue))
        }
      }
      group.addTask {
        for try await buffer in execution.standardError {
          continuation.yield(.standardError(buffer.dataValue))
        }
      }
      try await group.waitForAll()
    }
  }

  // MARK: - Configuration

  private func subprocessEnvironment(for command: Command) -> Subprocess.Environment {
    let merged = command.resolvedEnvironment
    var custom: [Subprocess.Environment.Key: String] = [:]
    custom.reserveCapacity(merged.count)
    for (key, value) in merged {
      custom[Subprocess.Environment.Key(stringLiteral: key)] = value
    }
    return .custom(custom)
  }

  private func platformOptions() -> PlatformOptions {
    var options = PlatformOptions()
    options.teardownSequence = [
      .gracefulShutDown(allowedDurationToNextStep: .seconds(2))
    ]
    return options
  }

  private func withTimeout<T: Sendable>(
    of command: Command,
    _ body: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    guard let timeout = command.timeout else { return try await body() }
    return try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await body() }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw CommandError(kind: .timedOut, command: command)
      }
      let first = try await group.next()!
      group.cancelAll()
      return first
    }
  }
}

extension SubprocessOutputSequence.Buffer {
  fileprivate var dataValue: Data {
    unsafe self.withUnsafeBytes { unsafe Data($0) }
  }
}
