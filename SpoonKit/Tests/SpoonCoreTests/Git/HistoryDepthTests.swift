import Foundation
import Testing

@testable import SpoonCore

@Suite("History depth")
struct HistoryDepthTests {
  @Test func depthsBecomeFetchFlags() {
    #expect(HistoryDepth.commits(50).arguments == ["--deepen=50"])
    #expect(HistoryDepth.commits(0).arguments == ["--deepen=1"])
    #expect(HistoryDepth.full.arguments == ["--unshallow"])
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12))!
    #expect(HistoryDepth.since(date).arguments == ["--shallow-since=2026-03-07"])
  }
}
