import Foundation
import SQLite3
import Testing

@testable import UnsealedSpellbookCore

@Suite("Low-overhead local collection")
struct CollectorAcceptanceTests {
  @Test("Unchanged JSONL files are not reread and appended snapshots replace partial ones")
  func incrementalJSONLCollection() async throws {
    let fixture = try FixtureDirectory()
    defer { fixture.remove() }
    let logURL = fixture.claude.appendingPathComponent("session.jsonl")
    let partial =
      #"{"type":"assistant","sessionId":"session_1","timestamp":"2026-07-12T01:02:02Z","message":{"id":"msg_1","usage":{"input_tokens":12,"output_tokens":1,"cache_read_input_tokens":20,"cache_creation_input_tokens":3}}}"#
      + "\n"
    try Data(partial.utf8).write(to: logURL)
    let collector = LocalUsageCollector(locations: fixture.locations)
    let interval = DateInterval(start: .distantPast, end: .distantFuture)

    let first = await collector.collect(interval: interval)
    let unchanged = await collector.collect(interval: interval)

    #expect(first.snapshot.total.total == 36)
    #expect(first.diagnostics.filesRead == 1)
    #expect(unchanged.snapshot.total.total == 36)
    #expect(unchanged.diagnostics.filesRead == 0)
    #expect(unchanged.diagnostics.bytesRead == 0)

    let final =
      #"{"type":"assistant","sessionId":"session_1","timestamp":"2026-07-12T01:02:03Z","message":{"id":"msg_1","usage":{"input_tokens":12,"output_tokens":5,"cache_read_input_tokens":20,"cache_creation_input_tokens":3}}}"#
      + "\n"
    let handle = try FileHandle(forWritingTo: logURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(final.utf8))
    try handle.close()

    let appended = await collector.collect(interval: interval)

    #expect(appended.snapshot.total.total == 40)
    #expect(appended.diagnostics.filesRead == 1)
    #expect(appended.diagnostics.bytesRead == final.utf8.count)
  }

  @Test("An unchanged OpenCode database is queried once")
  func openCodeDatabaseCaching() async throws {
    let fixture = try FixtureDirectory()
    defer { fixture.remove() }
    try createOpenCodeDatabase(at: fixture.openCodeDatabase)
    let collector = LocalUsageCollector(locations: fixture.locations)
    let interval = DateInterval(start: .distantPast, end: .distantFuture)

    let first = await collector.collect(interval: interval)
    let unchanged = await collector.collect(interval: interval)

    #expect(first.snapshot.providers[.openCode]?.total == 25)
    #expect(first.diagnostics.databaseRowsRead == 1)
    #expect(unchanged.snapshot.providers[.openCode]?.total == 25)
    #expect(unchanged.diagnostics.databaseRowsRead == 0)
  }

  @Test("Codex model context survives an incremental append")
  func codexContextSurvivesAppend() async throws {
    let fixture = try FixtureDirectory()
    defer { fixture.remove() }
    let logURL = fixture.codex.appendingPathComponent("session.jsonl")
    let context =
      #"{"timestamp":"2026-07-12T01:02:02Z","type":"turn_context","payload":{"model":"gpt-test","effort":"high"}}"#
      + "\n"
    try Data(context.utf8).write(to: logURL)
    let collector = LocalUsageCollector(locations: fixture.locations)
    let interval = DateInterval(start: .distantPast, end: .distantFuture)

    #expect(await collector.collect(interval: interval).events.isEmpty)

    let usage =
      #"{"timestamp":"2026-07-12T01:02:03Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20,"cached_input_tokens":10,"output_tokens":5,"reasoning_output_tokens":2,"total_tokens":25},"total_token_usage":{"input_tokens":20,"cached_input_tokens":10,"output_tokens":5,"reasoning_output_tokens":2,"total_tokens":25}}}}"#
      + "\n"
    let handle = try FileHandle(forWritingTo: logURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(usage.utf8))
    try handle.close()

    let result = await collector.collect(interval: interval)

    #expect(
      result.events.first?.model
        == ModelIdentity(
          tool: .codex,
          name: "gpt-test",
          variant: "high"
        ))
  }

  @Test("Disabled providers are neither scanned nor included")
  func providerSelection() async throws {
    let fixture = try FixtureDirectory()
    defer { fixture.remove() }
    let logURL = fixture.claude.appendingPathComponent("session.jsonl")
    let usage =
      #"{"type":"assistant","sessionId":"session_1","timestamp":"2026-07-12T01:02:02Z","message":{"id":"msg_1","usage":{"input_tokens":10,"output_tokens":2}}}"#
      + "\n"
    try Data(usage.utf8).write(to: logURL)
    let collector = LocalUsageCollector(locations: fixture.locations)
    let interval = DateInterval(start: .distantPast, end: .distantFuture)

    let result = await collector.collect(interval: interval, enabledProviders: [.codex])

    #expect(result.events.isEmpty)
    #expect(result.diagnostics.filesDiscovered == 0)
    #expect(result.diagnostics.filesRead == 0)
  }

  @Test("Replacing or deleting a log removes its previous contribution")
  func replacedAndDeletedLogs() async throws {
    let fixture = try FixtureDirectory()
    defer { fixture.remove() }
    let logURL = fixture.claude.appendingPathComponent("session.jsonl")
    let old =
      #"{"type":"assistant","sessionId":"session_1","timestamp":"2026-07-12T01:02:02Z","message":{"id":"old","usage":{"input_tokens":10,"output_tokens":1}}}"#
      + "\n"
    try Data(old.utf8).write(to: logURL)
    let collector = LocalUsageCollector(locations: fixture.locations)
    let interval = DateInterval(start: .distantPast, end: .distantFuture)
    #expect(await collector.collect(interval: interval).snapshot.total.total == 11)

    let replacement =
      #"{"type":"assistant","sessionId":"session_2","timestamp":"2026-07-12T01:02:03Z","message":{"id":"replacement_message","usage":{"input_tokens":20,"output_tokens":5,"cache_read_input_tokens":30}}}"#
      + "\n"
    try Data(replacement.utf8).write(to: logURL, options: .atomic)
    #expect(await collector.collect(interval: interval).snapshot.total.total == 55)

    try FileManager.default.removeItem(at: logURL)
    #expect(await collector.collect(interval: interval).snapshot.total.total == 0)
  }

  @Test("Oversized JSONL records are dropped without hiding following usage")
  func boundedLineBuffer() async throws {
    let fixture = try FixtureDirectory()
    defer { fixture.remove() }
    let logURL = fixture.claude.appendingPathComponent("session.jsonl")
    let valid =
      #"{"type":"assistant","sessionId":"session_1","timestamp":"2026-07-12T01:02:02Z","message":{"id":"msg_1","usage":{"input_tokens":10,"output_tokens":2}}}"#
      + "\n"
    var data = Data(repeating: 0x78, count: 512 * 1_024 + 1)
    data.append(0x0A)
    data.append(Data(valid.utf8))
    try data.write(to: logURL)
    let collector = LocalUsageCollector(locations: fixture.locations)

    let result = await collector.collect(
      interval: DateInterval(start: .distantPast, end: .distantFuture)
    )

    #expect(result.snapshot.total.total == 12)
    #expect(result.diagnostics.oversizedRecords == 1)
  }

  private func createOpenCodeDatabase(at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
      throw FixtureError.sqlite
    }
    defer { sqlite3_close(database) }
    let json =
      #"{"id":"msg_1","role":"assistant","time":{"created":1783827723000},"tokens":{"input":8,"output":4,"reasoning":2,"cache":{"read":10,"write":1}}}"#
    let escaped = json.replacingOccurrences(of: "'", with: "''")
    let sql = """
      CREATE TABLE message (id TEXT PRIMARY KEY, time_created INTEGER NOT NULL, data TEXT NOT NULL);
      INSERT INTO message VALUES ('msg_1', 1783827723000, '\(escaped)');
      """
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
      throw FixtureError.sqlite
    }
  }

  private struct FixtureDirectory {
    let root: URL
    let claude: URL
    let codex: URL
    let openCodeDatabase: URL

    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      claude = root.appendingPathComponent("claude")
      codex = root.appendingPathComponent("codex")
      openCodeDatabase = root.appendingPathComponent("opencode.db")
      try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
    }

    var locations: LocalUsageLocations {
      LocalUsageLocations(
        claudeCodeDirectory: claude,
        codexDirectory: codex,
        openCodeDatabase: openCodeDatabase
      )
    }

    func remove() {
      try? FileManager.default.removeItem(at: root)
    }
  }

  private enum FixtureError: Error {
    case sqlite
  }
}
