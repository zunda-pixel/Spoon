import Foundation
import Synchronization

@testable import SpoonCore

/// Scripted `CommandRunning` that replays canned results and records every
/// invocation, so tests can assert the exact argv git receives.
final class FakeCommandRunner: CommandRunning, Sendable {
  private struct State {
    var stubs: [(arguments: [String], result: CommandResult)] = []
    var invocations: [Command] = []
  }

  private let state = Mutex(State())

  /// Registers a result for an exact-match argument list (including the
  /// `-c color.ui=false …` base flags — argv drift should fail tests).
  func stub(arguments: [String], stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
    let result = CommandResult(
      exitCode: exitCode,
      standardOutput: Data(stdout.utf8),
      standardError: Data(stderr.utf8)
    )
    state.withLock { $0.stubs.append((arguments, result)) }
  }

  var invocations: [Command] {
    state.withLock { $0.invocations }
  }

  func run(_ command: Command) async throws -> CommandResult {
    let stubbed = state.withLock { state -> CommandResult? in
      state.invocations.append(command)
      return state.stubs.first(where: { $0.arguments == command.arguments })?.result
    }
    guard let stubbed else {
      throw CommandError(
        kind: .launchFailed(reason: "no stub for: \(command.arguments.joined(separator: " "))"),
        command: command
      )
    }
    return stubbed
  }

  func events(_ command: Command) -> AsyncThrowingStream<CommandEvent, any Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          let result = try await run(command)
          if !result.standardOutput.isEmpty {
            continuation.yield(.standardOutput(result.standardOutput))
          }
          if !result.standardError.isEmpty {
            continuation.yield(.standardError(result.standardError))
          }
          continuation.yield(.exited(result.exitCode))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }
}
