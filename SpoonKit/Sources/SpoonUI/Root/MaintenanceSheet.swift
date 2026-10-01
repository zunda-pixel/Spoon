import SpoonCore
import SwiftUI

/// How the repository's objects are stored, an optimize-now action
/// (`git gc`), and git's scheduled background maintenance.
@MainActor
struct MaintenanceSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var storage: RepositoryStorage?
  @State private var sizeBefore: Int?
  @State private var aggressive = false
  @State private var isOptimizing = false
  @State private var background = false
  @State private var backgroundLoaded = false

  var body: some View {
    VStack(spacing: 0) {
      Text("Maintenance for \(model.repository.name)")
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .top], 16)
      Form {
        Section("Storage") {
          if let storage {
            LabeledContent("Size on disk", value: bytes(storage.totalBytes))
            LabeledContent(
              "Packed",
              value:
                "\(storage.packedObjects.formatted()) objects in \(storage.packs) \(storage.packs == 1 ? "pack" : "packs")"
            )
            LabeledContent(
              "Loose",
              value: "\(storage.looseObjects.formatted()) objects, \(bytes(storage.looseBytes))")
            if storage.garbageBytes > 0 {
              LabeledContent("Garbage", value: bytes(storage.garbageBytes))
            }
          } else {
            ProgressView()
          }
        }
        Section {
          HStack {
            Button(isOptimizing ? "Optimizing…" : "Optimize Now", action: optimize)
              .disabled(isOptimizing || model.isBusy)
            if isOptimizing {
              ProgressView().controlSize(.small)
            } else if let sizeBefore, let storage, sizeBefore > storage.totalBytes {
              Text("Saved \(bytes(sizeBefore - storage.totalBytes))")
                .foregroundStyle(.secondary)
            }
          }
          Toggle("Aggressive (recompress everything; much slower)", isOn: $aggressive)
            .disabled(isOptimizing)
        } header: {
          Text("Optimize")
        } footer: {
          Text(
            "Packs loose objects, removes unreachable ones after git’s grace period, and compresses packs (git gc)."
          )
        }
        Section {
          Toggle("Run maintenance in the background", isOn: $background)
            .disabled(!backgroundLoaded || model.isBusy)
            .onChange(of: background) { _, enabled in
              guard backgroundLoaded else { return }
              Task { await model.setBackgroundMaintenance(enabled) }
            }
        } header: {
          Text("Background")
        } footer: {
          Text(
            "git maintenance start registers this repository and schedules hourly, daily, and weekly jobs with launchd that prefetch from remotes and keep storage compact. Turning it off unregisters only this repository."
          )
        }
      }
      .formStyle(.grouped)
      Divider()
      HStack {
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
      .padding(12)
    }
    .frame(width: 520, height: 560)
    .task {
      storage = try? await model.storage()
      background = await model.isBackgroundMaintenanceEnabled()
      backgroundLoaded = true
    }
  }

  private func bytes(_ count: Int) -> String {
    Int64(count).formatted(.byteCount(style: .file))
  }

  private func optimize() {
    sizeBefore = storage?.totalBytes
    isOptimizing = true
    Task {
      await model.optimize(aggressive: aggressive)
      storage = try? await model.storage()
      isOptimizing = false
    }
  }
}
