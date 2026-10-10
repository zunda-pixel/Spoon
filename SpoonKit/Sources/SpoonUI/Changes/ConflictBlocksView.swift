import SpoonCore
import SwiftUI

/// The conflicts of one file, each resolvable on its own by taking one
/// side, or both.
@MainActor
struct ConflictBlocksView: View {
  let model: RepositoryModel
  let path: String
  let document: ConflictDocument
  /// Called after the file was rewritten, so the caller reloads it.
  let onChange: () -> Void

  var body: some View {
    let blocks = document.blocks
    VStack(spacing: 0) {
      HStack {
        Label(
          blocks.count == 1 ? "1 conflict left" : "\(blocks.count) conflicts left",
          systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.orange)
        Spacer()
        RestoreConflictMarkersButton(model: model, path: path, onChange: onChange)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          ForEach(Array(document.outline().enumerated()), id: \.offset) { _, item in
            switch item {
            case .context(let lines):
              ConflictLines(lines: lines, style: .context)
            case .omitted(let count):
              Text(count == 1 ? "⋯ 1 unchanged line" : "⋯ \(count) unchanged lines")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            case .conflict(let block):
              ConflictBlockView(
                block: block,
                total: blocks.count,
                kind: model.sequencerState?.kind,
                isDisabled: model.isBusy
              ) { choice in
                Task {
                  await model.resolveConflictBlock(block, in: path, using: choice)
                  onChange()
                }
              }
            }
          }
        }
        .padding(12)
      }
    }
  }
}

/// Shown once a conflicted file has no markers left.
@MainActor
struct ConflictsResolvedBar: View {
  let model: RepositoryModel
  let path: String
  let onChange: () -> Void

  @State private var confirmingForget = false

  var body: some View {
    HStack {
      if model.rerereResolvedPaths.contains(path) {
        Label("Resolved from a recorded resolution", systemImage: "arrow.triangle.2.circlepath")
          .foregroundStyle(.green)
          .help(
            "rerere applied how this conflict was resolved before; review it, then mark it resolved"
          )
        Button("Forget Resolution…") { confirmingForget = true }
          .disabled(model.isBusy)
          .confirmationDialog(
            "Forget the recorded resolution for “\(path)”?", isPresented: $confirmingForget
          ) {
            Button("Forget Resolution", role: .destructive) {
              Task {
                await model.forgetRecordedResolution(path: path)
                onChange()
              }
            }
          } message: {
            Text(
              "The conflict markers come back so you can resolve it again; the new resolution is recorded instead."
            )
          }
      } else {
        Label("No conflict markers left", systemImage: "checkmark.circle")
          .foregroundStyle(.green)
      }
      Spacer()
      RestoreConflictMarkersButton(model: model, path: path, onChange: onChange)
      Button("Mark Resolved") {
        Task { await model.stage(paths: [path]) }
      }
      .disabled(model.isBusy)
      .help("Stage the file as resolved")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }
}

@MainActor
private struct RestoreConflictMarkersButton: View {
  let model: RepositoryModel
  let path: String
  let onChange: () -> Void
  @State private var isConfirming = false

  var body: some View {
    Button("Restore Conflict Markers…") { isConfirming = true }
      .disabled(model.isBusy)
      .help("Start this file’s conflicts over")
      .confirmationDialog(
        "Restore the conflict markers in “\(path)”?",
        isPresented: $isConfirming
      ) {
        Button("Restore Conflict Markers", role: .destructive) {
          Task {
            await model.restoreConflictMarkers(path: path)
            onChange()
          }
        }
      } message: {
        Text(
          "Every conflict in the file comes back as git first wrote it. Conflicts you resolved and other edits to the file are discarded."
        )
      }
  }
}

@MainActor
private struct ConflictBlockView: View {
  let block: ConflictBlock
  let total: Int
  let kind: SequencerState.Kind?
  let isDisabled: Bool
  let resolve: (ConflictChoice) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      side(.ours, label: block.oursLabel, lines: block.ours)
      if let base = block.base {
        Divider()
        sideHeader("Common Ancestor", label: block.baseLabel ?? "", tint: .secondary)
        ConflictLines(lines: base, style: .base)
      }
      Divider()
      side(.theirs, label: block.theirsLabel, lines: block.theirs)
    }
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    .padding(.vertical, 4)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Conflict \(block.index + 1) of \(total)")
  }

  private var header: some View {
    AdaptiveActionsLayout(spacing: 8, rowSpacing: 6) {
      title
      WrappingLayout { buttons }
    }
    .controlSize(.small)
    .disabled(isDisabled)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.5))
  }

  private var title: some View {
    HStack(spacing: 8) {
      Text("Conflict \(block.index + 1) of \(total)")
        .font(.headline)
      Text("Line \(block.startLine)")
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var buttons: some View {
    let ours = FileStatusEntry.ConflictSide.ours.shortName(during: kind)
    Button("Use \(ours)") { resolve(.ours) }
    Button("Use \(FileStatusEntry.ConflictSide.theirs.shortName(during: kind))") {
      resolve(.theirs)
    }
    Button("Use Both") { resolve(.both) }
      .help("Keep both versions, \(ours.lowercased()) first")
  }

  private func side(
    _ side: FileStatusEntry.ConflictSide, label: String, lines: [String]
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      sideHeader(
        side.displayName(during: kind),
        label: label,
        tint: side == .ours ? .green : .blue
      )
      ConflictLines(lines: lines, style: side == .ours ? .ours : .theirs)
    }
  }

  private func sideHeader(_ title: String, label: String, tint: Color) -> some View {
    HStack(spacing: 6) {
      Text(title)
        .font(.caption.bold())
        .foregroundStyle(tint)
      if !label.isEmpty {
        Text(label)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .padding(.horizontal, 10)
    .padding(.top, 6)
    .padding(.bottom, 2)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(tint.opacity(0.08))
  }
}

@MainActor
private struct ConflictLines: View {
  enum Style {
    case context, ours, base, theirs

    var background: Color {
      switch self {
      case .context: .clear
      case .ours: .green.opacity(0.08)
      case .base: .secondary.opacity(0.06)
      case .theirs: .blue.opacity(0.08)
      }
    }
  }

  let lines: [String]
  let style: Style

  var body: some View {
    if style != .context && lines.isEmpty {
      Text("No lines")
        .font(.callout.italic())
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background)
    } else if !lines.isEmpty {
      Text(lines.map(Self.trimmingLineEnding).joined(separator: "\n"))
        .font(.callout.monospaced())
        .foregroundStyle(style == .context ? .secondary : .primary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10)
        .padding(.vertical, style == .context ? 0 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background)
    }
  }

  private static func trimmingLineEnding(_ line: String) -> String {
    var line = Substring(line)
    while let last = line.last, last == "\n" || last == "\r\n" || last == "\r" {
      line = line.dropLast()
    }
    return String(line)
  }
}
