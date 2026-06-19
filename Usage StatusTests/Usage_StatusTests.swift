import Foundation
import Testing
@testable import Usage_Status

struct Usage_StatusTests {
    @Test func parsesLatestCodexRateLimitSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("session.jsonl")
        let old = #"{"timestamp":"2026-06-19T08:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":20,"window_minutes":300,"resets_at":1781870000},"secondary":{"used_percent":4,"window_minutes":10080,"resets_at":1782450000}}}}"#
        let latest = #"{"timestamp":"2026-06-19T09:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":60.0,"window_minutes":300,"resets_at":1781873009},"secondary":{"used_percent":9.0,"window_minutes":10080,"resets_at":1782459809}}}}"#
        try Data("\(old)\n\(latest)\n".utf8).write(to: file)

        let result = try #require(UsageLoader.latestCodexSnapshot(in: file))
        #expect(result.primary?.usedPercent == 60)
        #expect(result.primary?.windowMinutes == 300)
        #expect(result.secondary?.usedPercent == 9)
        #expect(result.secondary?.windowMinutes == 10_080)
    }

    @Test func ignoresMalformedAndUnrelatedRows() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not-json\n{\"payload\":{\"type\":\"agent_message\"}}\n".utf8).write(to: file)

        #expect(UsageLoader.latestCodexSnapshot(in: file) == nil)
    }

    @Test func clampsProviderPercentages() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let row = #"{"payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":140,"window_minutes":300},"secondary":{"used_percent":-5,"window_minutes":10080}}}}"#
        try Data(row.utf8).write(to: file)

        let result = try #require(UsageLoader.latestCodexSnapshot(in: file))
        #expect(result.primary?.usedPercent == 100)
        #expect(result.secondary?.usedPercent == 0)
    }
}
