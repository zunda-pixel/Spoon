public import Foundation

import CoreServices

/// Streams batches of changed directory paths under a root via FSEvents.
///
/// This file is the app's only unsafe-interop quarantine zone: the FSEvents
/// C API needs raw pointers for its context and path array. Nothing outside
/// this file touches `unsafe` constructs.
public enum FSEventsWatcher {
  /// Directory-granularity change events (no per-file flags — cheaper, and
  /// classification only needs directories). The stream ends when the
  /// consumer cancels.
  public static func changes(under root: URL) -> AsyncStream<[String]> {
    AsyncStream { continuation in
      let queue = DispatchQueue(label: "com.spoon.fsevents")

      final class Box {
        let continuation: AsyncStream<[String]>.Continuation
        init(_ continuation: AsyncStream<[String]>.Continuation) {
          self.continuation = continuation
        }
      }

      let box = Box(continuation)
      let info = unsafe Unmanaged.passRetained(box).toOpaque()
      var context = unsafe FSEventStreamContext(
        version: 0,
        info: info,
        retain: nil,
        release: nil,
        copyDescription: nil
      )

      let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
        guard let info = unsafe info else { return }
        let box = unsafe Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
        // Without kFSEventStreamCreateFlagUseCFTypes, eventPaths is char**.
        let paths = unsafe eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
        var changed: [String] = []
        changed.reserveCapacity(count)
        for index in 0..<count {
          if let path = unsafe paths[index] {
            changed.append(unsafe String(cString: path))
          }
        }
        if !changed.isEmpty {
          box.continuation.yield(changed)
        }
      }

      let created = unsafe FSEventStreamCreate(
        kCFAllocatorDefault,
        callback,
        &context,
        [root.path(percentEncoded: false)] as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        0.3,  // seconds of kernel-side coalescing
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
      )

      guard let stream = unsafe created else {
        unsafe Unmanaged<Box>.fromOpaque(info).release()
        continuation.finish()
        return
      }

      // FSEventStreamRef is a CF object without Sendable annotation; hand
      // it to the termination closure through an @unchecked box.
      @unsafe
      final class StreamHandle: @unchecked Sendable {
        let stream: FSEventStreamRef
        let info: UnsafeMutableRawPointer
        init(stream: FSEventStreamRef, info: UnsafeMutableRawPointer) {
          unsafe self.stream = stream
          unsafe self.info = info
        }
      }
      let handle = unsafe StreamHandle(stream: stream, info: info)

      unsafe FSEventStreamSetDispatchQueue(stream, queue)
      unsafe FSEventStreamStart(stream)

      continuation.onTermination = { _ in
        queue.async {
          unsafe FSEventStreamStop(handle.stream)
          unsafe FSEventStreamInvalidate(handle.stream)
          unsafe FSEventStreamRelease(handle.stream)
          unsafe Unmanaged<Box>.fromOpaque(handle.info).release()
        }
      }
    }
  }
}
