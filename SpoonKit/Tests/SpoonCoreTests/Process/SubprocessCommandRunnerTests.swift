import Foundation
import Testing

@testable import SpoonCore

@Suite("SubprocessCommandRunner")
struct SubprocessCommandRunnerTests {
  private let runner = SubprocessCommandRunner()

  @Test func capturesStandardOutput() async throws {
    let result = try await runner.run(
      Command(executable: URL(filePath: "/bin/echo"), arguments: ["hello", "world"])
    )
    #expect(result.exitCode == 0)
    #expect(result.standardOutputText == "hello world\n")
  }

  @Test func capturesStandardErrorAndExitCode() async throws {
    let result = try await runner.run(
      Command(
        executable: URL(filePath: "/bin/sh"),
        arguments: ["-c", "echo oops >&2; exit 3"]
      )
    )
    #expect(result.exitCode == 3)
    #expect(!result.isSuccess)
    #expect(result.standardErrorText == "oops\n")
    #expect(throws: CommandError.self) {
      try result.checkSuccess(of: Command(executable: URL(filePath: "/bin/sh")))
    }
  }

  @Test func forwardsStandardInput() async throws {
    let result = try await runner.run(
      Command(
        executable: URL(filePath: "/bin/cat"),
        standardInput: Data("piped\n".utf8)
      )
    )
    #expect(result.standardOutputText == "piped\n")
  }

  @Test func appliesEnvironmentOverrides() async throws {
    let result = try await runner.run(
      Command(
        executable: URL(filePath: "/bin/sh"),
        arguments: ["-c", "printf %s \"$SPOON_TEST_VAR\""],
        environment: ["SPOON_TEST_VAR": "42"]
      )
    )
    #expect(result.standardOutputText == "42")
  }

  @Test func timesOut() async throws {
    let command = Command(
      executable: URL(filePath: "/bin/sleep"),
      arguments: ["30"],
      timeout: .milliseconds(200)
    )
    let started = ContinuousClock.now
    await #expect(throws: CommandError.self) {
      try await runner.run(command)
    }
    // The child must actually be torn down promptly, not linger for 30 s.
    #expect(ContinuousClock.now - started < .seconds(10))
  }

  @Test func streamsBothPipesAndExit() async throws {
    let command = Command(
      executable: URL(filePath: "/bin/sh"),
      arguments: ["-c", "echo out1; echo err1 >&2; echo out2"]
    )
    var stdout = Data()
    var stderr = Data()
    var exitCode: Int32?
    for try await event in runner.events(command) {
      switch event {
      case .standardOutput(let data): stdout.append(data)
      case .standardError(let data): stderr.append(data)
      case .exited(let code): exitCode = code
      }
    }
    #expect(String(decoding: stdout, as: UTF8.self) == "out1\nout2\n")
    #expect(String(decoding: stderr, as: UTF8.self) == "err1\n")
    #expect(exitCode == 0)
  }

  @Test func launchFailureThrows() async {
    await #expect(throws: CommandError.self) {
      try await runner.run(
        Command(executable: URL(filePath: "/nonexistent/tool"))
      )
    }
  }
}
