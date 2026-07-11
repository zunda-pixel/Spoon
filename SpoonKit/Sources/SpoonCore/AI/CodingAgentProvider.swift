public import Foundation

/// A headless coding agent (Claude Code, Codex) driven through its CLI.
/// v1 surface is buffered request/response; streaming can layer on later
/// without changing callers.
public protocol CodingAgentProvider: Sendable {
  var id: AIProviderID { get }

  /// The CLI is installed and resolvable.
  func isAvailable() async -> Bool

  /// Pure generation from an injected prompt — no repository tool access.
  func generateCommitMessage(prompt: String) async throws -> String

  /// Agentic read-only review inside `repository`; returns the report
  /// decoded from schema-constrained output.
  func review(prompt: String, repository: URL) async throws -> ReviewReport
}

/// Shared plumbing for CLI-backed providers.
enum AgentCLI {
  /// Extracts the first top-level JSON object from model output that may
  /// be wrapped in prose or code fences, then decodes it.
  static func decodeReport(from text: String) throws -> ReviewReport {
    let decoder = JSONDecoder()
    if let data = text.data(using: .utf8),
      let report = try? decoder.decode(ReviewReport.self, from: data)
    {
      return report
    }
    // Strip ```json fences.
    var candidate = text
    if let fenceStart = candidate.range(of: "```json") ?? candidate.range(of: "```") {
      candidate = String(candidate[fenceStart.upperBound...])
      if let fenceEnd = candidate.range(of: "```") {
        candidate = String(candidate[..<fenceEnd.lowerBound])
      }
    }
    // Balanced top-level {...} scan.
    if let start = candidate.firstIndex(of: "{") {
      var depth = 0
      var inString = false
      var previous: Character = " "
      var index = start
      while index < candidate.endIndex {
        let char = candidate[index]
        if inString {
          if char == "\"" && previous != "\\" { inString = false }
        } else {
          switch char {
          case "\"": inString = true
          case "{": depth += 1
          case "}":
            depth -= 1
            if depth == 0 {
              let json = candidate[start...index]
              if let data = json.data(using: .utf8),
                let report = try? decoder.decode(ReviewReport.self, from: data)
              {
                return report
              }
            }
          default: break
          }
        }
        previous = char
        index = candidate.index(after: index)
      }
    }
    throw AIError(kind: .outputUnparseable, rawOutput: text)
  }

  static func requireSuccess(_ result: CommandResult, provider: AIProviderID) throws {
    guard result.isSuccess else {
      throw AIError(
        kind: .cliFailed(
          exitCode: result.exitCode,
          stderrExcerpt: CommandError.excerpt(from: result.standardError)
        ),
        rawOutput: result.standardOutputText
      )
    }
  }
}
