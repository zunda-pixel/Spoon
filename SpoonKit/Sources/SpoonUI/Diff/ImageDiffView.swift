import AppKit
import SpoonCore
import SwiftUI
import UniformTypeIdentifiers

/// Reads both sides of a binary file diff so images can be shown instead of
/// "Binary file".
@MainActor
struct DiffImageLoader {
  /// The versions to try for each side, in order; empty when that side has
  /// no file (e.g. the old side of an added file).
  struct Versions {
    var old: [FileVersion]
    var new: [FileVersion]
  }

  let model: RepositoryModel
  /// Changes whenever the files behind the diff may have changed although
  /// the patch (always "Binary files differ") did not.
  var contentID: String = ""
  let versions: (FileDiff) -> Versions

  /// Whether `diff` is a binary file the preview can try to show.
  static func isImage(_ diff: FileDiff) -> Bool {
    guard diff.isBinary else { return false }
    let fileExtension = (diff.path as NSString).pathExtension
    return UTType(filenameExtension: fileExtension)?.conforms(to: .image) == true
  }

  /// Versions for a diff between two revisions; the old revision is `nil`
  /// for a root commit.
  static func revisions(
    model: RepositoryModel, old: String?, new: String
  ) -> DiffImageLoader {
    DiffImageLoader(model: model) { diff in
      Versions(
        old: diff.kind == .added ? [] : old.map { [.revision($0)] } ?? [],
        new: diff.kind == .deleted ? [] : [.revision(new)]
      )
    }
  }

  func load(_ diff: FileDiff) async -> ImageDiffSides {
    let versions = versions(diff)
    async let old = image(path: diff.oldPath ?? diff.path, candidates: versions.old)
    async let new = image(path: diff.path, candidates: versions.new)
    return await ImageDiffSides(old: old, new: new)
  }

  private func image(path: String, candidates: [FileVersion]) async -> ImageDiffSide? {
    guard !candidates.isEmpty else { return nil }
    for version in candidates {
      guard let data = try? await model.fileContents(path: path, at: version) else { continue }
      guard let image = NSImage(data: data), image.isValid else { return .unreadable }
      return .image(image, byteCount: data.count)
    }
    return .unreadable
  }
}

enum ImageDiffSide {
  case image(NSImage, byteCount: Int)
  /// The file exists on this side but could not be read or decoded.
  case unreadable
}

struct ImageDiffSides {
  var old: ImageDiffSide?
  var new: ImageDiffSide?
}

/// Side-by-side preview of an image's old and new versions.
@MainActor
struct ImageDiffView: View {
  let diff: FileDiff
  let loader: DiffImageLoader

  @State private var sides: ImageDiffSides?

  private struct LoadKey: Hashable {
    let diff: FileDiff
    let contentID: String
  }

  var body: some View {
    Group {
      if let sides {
        HStack(alignment: .top, spacing: 12) {
          if diff.kind != .added {
            ImageDiffPane(title: "Before", side: sides.old, tint: .red)
          }
          if diff.kind != .deleted {
            ImageDiffPane(title: "After", side: sides.new, tint: .green)
          }
        }
        .padding(12)
      } else {
        ProgressView()
          .controlSize(.small)
          .padding(12)
      }
    }
    .task(id: LoadKey(diff: diff, contentID: loader.contentID)) {
      let loaded = await loader.load(diff)
      guard !Task.isCancelled else { return }
      sides = loaded
    }
  }
}

@MainActor
private struct ImageDiffPane: View {
  let title: String
  let side: ImageDiffSide?
  let tint: Color

  private static let maximumHeight: CGFloat = 360

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
      switch side {
      case .image(let image, let byteCount):
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .frame(
            maxWidth: min(image.size.width, 480),
            maxHeight: min(image.size.height, Self.maximumHeight),
            alignment: .topLeading
          )
          .background(CheckerboardBackground())
          .border(.separator)
          .accessibilityLabel("\(title) image")
          .accessibilityValue(details(image, byteCount: byteCount))
        Text(details(image, byteCount: byteCount))
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      case .unreadable, nil:
        Label("Image not available", systemImage: "photo.badge.exclamationmark")
          .foregroundStyle(.secondary)
      }
    }
  }

  private func details(_ image: NSImage, byteCount: Int) -> String {
    // Pixel size, not points: a @2x PNG would otherwise report half its size.
    var width = Int(image.size.width)
    var height = Int(image.size.height)
    if let representation = image.representations.first,
      representation.pixelsWide > 0, representation.pixelsHigh > 0
    {
      width = representation.pixelsWide
      height = representation.pixelsHigh
    }
    let bytes = byteCount.formatted(.byteCount(style: .file))
    return "\(width) × \(height) px · \(bytes)"
  }
}

/// Shows transparent areas of an image the way image editors do.
private struct CheckerboardBackground: View {
  var body: some View {
    Canvas { context, size in
      let square: CGFloat = 8
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .style(.background))
      for row in 0..<Int((size.height / square).rounded(.up)) {
        for column in 0..<Int((size.width / square).rounded(.up))
        where (row + column).isMultiple(of: 2) {
          let rect = CGRect(
            x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square)
          context.fill(Path(rect), with: .style(.quaternary))
        }
      }
    }
    .accessibilityHidden(true)
  }
}
