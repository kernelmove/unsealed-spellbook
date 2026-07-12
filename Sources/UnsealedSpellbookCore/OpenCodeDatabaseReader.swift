import Foundation
import SQLite3

enum OpenCodeDatabaseReader {
  static func read(_ url: URL, interval: DateInterval) throws -> DatabaseReadResult {
    var database: OpaquePointer?
    let uri = "file:\(url.path)?mode=ro"
    let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
    guard sqlite3_open_v2(uri, &database, flags, nil) == SQLITE_OK, let database else {
      if let database { sqlite3_close(database) }
      throw SQLiteReadError.open
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 100)
    guard sqlite3_exec(database, "PRAGMA query_only=ON; BEGIN", nil, nil, nil) == SQLITE_OK else {
      throw SQLiteReadError.query
    }
    defer { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) }

    let sql = """
      SELECT id, data
      FROM message
      WHERE time_created >= ?1
        AND time_created < ?2
        AND json_extract(data, '$.role') = 'assistant'
      ORDER BY time_created, id
      """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
      let statement
    else {
      throw SQLiteReadError.query
    }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_int64(statement, 1, milliseconds(interval.start))
    sqlite3_bind_int64(statement, 2, milliseconds(interval.end))

    let parser = OpenCodeParser()
    var events: [UsageEvent] = []
    var rejectedRecords = 0
    var rowsRead = 0

    // ponytail: DB/WAL changes requery today's rows to handle in-place updates; add tail reconciliation only if profiling demands it.
    var step = sqlite3_step(statement)
    while step == SQLITE_ROW {
      rowsRead += 1
      if let idBytes = sqlite3_column_text(statement, 0),
        let jsonBytes = sqlite3_column_text(statement, 1)
      {
        let id = String(cString: idBytes)
        let json = Data(bytes: jsonBytes, count: Int(sqlite3_column_bytes(statement, 1)))
        let result = parser.parse(json, sourceID: id)
        events.append(contentsOf: result.events)
        rejectedRecords += result.rejectedRecords
      } else {
        rejectedRecords += 1
      }
      step = sqlite3_step(statement)
    }
    guard step == SQLITE_DONE else { throw SQLiteReadError.query }

    return DatabaseReadResult(
      events: events,
      rowsRead: rowsRead,
      rejectedRecords: rejectedRecords
    )
  }

  private static func milliseconds(_ date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970 * 1_000)
  }
}

struct DatabaseReadResult {
  let events: [UsageEvent]
  let rowsRead: Int
  let rejectedRecords: Int
}

private enum SQLiteReadError: Error {
  case open
  case query
}
