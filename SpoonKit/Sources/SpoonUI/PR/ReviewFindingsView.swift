import SpoonCore
import SwiftUI

/// AI review results: summary + findings grouped by file with severity
/// icons and optional drop-in suggestions.
@MainActor
struct ReviewFindingsView: View {
  let report: ReviewReport
  let onDismiss: () -> Void

  init(report: ReviewReport, onDismiss: @escaping () -> Void) {
    self.report = report
    self.onDismiss = onDismiss
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Label("AI Review", systemImage: "sparkles")
          .font(.headline)
        Spacer()
        Button("Done", action: onDismiss)
          .keyboardShortcut(.cancelAction)
      }
      .padding(12)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text(report.summary)
            .textSelection(.enabled)

          if report.findings.isEmpty {
            Label("No issues found", systemImage: "checkmark.seal.fill")
              .foregroundStyle(.green)
          } else {
            ForEach(groupedFindings, id: \.file) { group in
              VStack(alignment: .leading, spacing: 8) {
                Text(group.file)
                  .font(.callout.monospaced().bold())
                  .lineLimit(1)
                  .truncationMode(.middle)
                ForEach(group.findings) { finding in
                  FindingRow(finding: finding)
                }
              }
            }
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(minWidth: 420, idealWidth: 520, minHeight: 320, idealHeight: 560)
  }

  private var groupedFindings: [(file: String, findings: [ReviewFinding])] {
    let sorted = report.findings.sorted { $0.severity.sortOrder < $1.severity.sortOrder }
    var order: [String] = []
    var byFile: [String: [ReviewFinding]] = [:]
    for finding in sorted {
      if byFile[finding.file] == nil { order.append(finding.file) }
      byFile[finding.file, default: []].append(finding)
    }
    return order.map { (file: $0, findings: byFile[$0] ?? []) }
  }
}

@MainActor
private struct FindingRow: View {
  let finding: ReviewFinding

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        severityBadge
        Text(finding.title)
          .fontWeight(.medium)
        if let line = finding.line {
          Text("L\(line)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
      }
      Text(finding.body)
        .font(.callout)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
      if let snippet = finding.anchorSnippet, !snippet.isEmpty {
        Text(snippet)
          .font(.caption.monospaced())
          .padding(6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
      }
      if let suggestion = finding.suggestion, !suggestion.isEmpty {
        Text(suggestion)
          .font(.caption.monospaced())
          .padding(6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .foregroundStyle(.green)
          .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
          .textSelection(.enabled)
      }
    }
    .padding(.leading, 4)
  }

  private var severityBadge: some View {
    Text(finding.severity.rawValue)
      .font(.caption2.bold())
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(severityColor.opacity(0.2), in: Capsule())
      .foregroundStyle(severityColor)
  }

  private var severityColor: Color {
    switch finding.severity {
    case .blocker: .red
    case .high: .orange
    case .medium: .yellow
    case .low: .blue
    case .nit: .gray
    }
  }
}
