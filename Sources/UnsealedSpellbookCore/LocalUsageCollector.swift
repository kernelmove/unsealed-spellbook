import Foundation

public struct LocalUsageLocations: Sendable {
  public let claudeCodeDirectory: URL
  public let codexDirectory: URL
  public let ohMyPiDirectory: URL?
  public let openCodeDatabase: URL

  public init(
    claudeCodeDirectory: URL,
    codexDirectory: URL,
    ohMyPiDirectory: URL? = nil,
    openCodeDatabase: URL
  ) {
    self.claudeCodeDirectory = claudeCodeDirectory
    self.codexDirectory = codexDirectory
    self.ohMyPiDirectory = ohMyPiDirectory
    self.openCodeDatabase = openCodeDatabase
  }

  public static var standard: LocalUsageLocations {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return LocalUsageLocations(
      claudeCodeDirectory: home.appendingPathComponent(".claude/projects"),
      codexDirectory: home.appendingPathComponent(".codex/sessions"),
      ohMyPiDirectory: home.appendingPathComponent(".omp/agent/sessions"),
      openCodeDatabase: home.appendingPathComponent(".local/share/opencode/opencode.db")
    )
  }
}

public struct CollectionDiagnostics: Equatable, Sendable {
  public let filesDiscovered: Int
  public let filesRead: Int
  public let bytesRead: Int
  public let databaseRowsRead: Int
  public let rejectedRecords: Int
  public let oversizedRecords: Int
  public let sourceErrors: Int
  public let elapsed: Duration
}

public struct CollectionResult: Sendable {
  public let snapshot: UsageSnapshot
  public let events: [UsageEvent]
  public let diagnostics: CollectionDiagnostics
}

public actor LocalUsageCollector {
  private static let chunkBytes = 256 * 1_024
  private static let maxLineBytes = 512 * 1_024

  private let locations: LocalUsageLocations
  private let sources: [JSONLSource]
  private var fileCache: [URL: LogCache] = [:]
  private var databaseCache: DatabaseCache?

  public init(locations: LocalUsageLocations = .standard) {
    self.locations = locations
    var sources: [JSONLSource] = [
      JSONLSource(
        provider: .claudeCode,
        directory: locations.claudeCodeDirectory,
        parser: ClaudeCodeParser()
      ),
      JSONLSource(
        provider: .codex,
        directory: locations.codexDirectory,
        parser: CodexParser()
      ),
    ]
    if let directory = locations.ohMyPiDirectory {
      sources.append(
        JSONLSource(
          provider: .ohMyPi,
          directory: directory,
          parser: OhMyPiParser()
        ))
    }
    self.sources = sources
  }

  public func collect(
    interval: DateInterval,
    enabledProviders: Set<AIProvider> = Set(AIProvider.allCases)
  ) -> CollectionResult {
    let clock = ContinuousClock()
    let started = clock.now
    var metrics = MutableDiagnostics()
    var activeFiles = Set<URL>()

    for source in sources where enabledProviders.contains(source.provider) {
      let files = discoverJSONL(in: source.directory, modifiedSince: interval.start)
      metrics.filesDiscovered += files.count
      for file in files {
        activeFiles.insert(file)
        do {
          try update(file: file, parser: source.parser, metrics: &metrics)
        } catch {
          metrics.sourceErrors += 1
        }
      }
    }
    fileCache = fileCache.filter { activeFiles.contains($0.key) }

    var events = fileCache.values.flatMap(\.events.values)
    if enabledProviders.contains(.openCode) {
      events.append(contentsOf: collectOpenCode(interval: interval, metrics: &metrics))
    } else {
      databaseCache = nil
    }
    let uniqueEvents = UsageAggregator.uniqueEvents(events, interval: interval)
    let snapshot = UsageAggregator.aggregate(uniqueEvents, interval: interval)
    return CollectionResult(
      snapshot: snapshot,
      events: uniqueEvents,
      diagnostics: metrics.snapshot(elapsed: started.duration(to: clock.now))
    )
  }

  private func discoverJSONL(in directory: URL, modifiedSince start: Date) -> [URL] {
    let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else { return [] }

    var files: [URL] = []
    for case let url as URL in enumerator where url.pathExtension == "jsonl" {
      guard
        let values = try? url.resourceValues(forKeys: Set(keys)),
        values.isRegularFile == true,
        (values.contentModificationDate ?? .distantPast) >= start
      else { continue }
      files.append(url)
    }
    return files
  }

  private func update(
    file: URL,
    parser: any UsageLogParser,
    metrics: inout MutableDiagnostics
  ) throws {
    let fingerprint = try fingerprint(file)
    if fileCache[file]?.fingerprint == fingerprint { return }

    var cache = fileCache[file] ?? LogCache()
    let mustRestart =
      cache.fingerprint.map {
        $0.inode != fingerprint.inode
          || fingerprint.size < cache.offset
          || (fingerprint.size == cache.offset && $0.modified != fingerprint.modified)
      } ?? false
    if mustRestart {
      cache = LogCache()
    }

    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    try handle.seek(toOffset: cache.offset)
    metrics.filesRead += 1

    var buffer = cache.tail
    var oversized = cache.tailIsOversized
    while let chunk = try handle.read(upToCount: Self.chunkBytes), !chunk.isEmpty {
      metrics.bytesRead += chunk.count
      var segmentStart = chunk.startIndex
      while let newline = chunk[segmentStart...].firstIndex(of: 0x0A) {
        append(chunk[segmentStart..<newline], to: &buffer, oversized: &oversized)
        finishLine(
          &buffer,
          oversized: &oversized,
          parser: parser,
          sourceID: file.path,
          cache: &cache,
          metrics: &metrics
        )
        segmentStart = chunk.index(after: newline)
      }
      if segmentStart < chunk.endIndex {
        append(chunk[segmentStart..<chunk.endIndex], to: &buffer, oversized: &oversized)
      }
    }

    cache.tail = buffer
    cache.tailIsOversized = oversized
    if !buffer.isEmpty, !oversized {
      let tailResult = parser.parse(
        buffer,
        sourceID: file.path,
        state: &cache.parserState
      )
      if !tailResult.events.isEmpty {
        merge(tailResult, into: &cache, metrics: &metrics, countRejected: false)
      }
    }
    cache.offset = UInt64(fingerprint.size)
    cache.fingerprint = fingerprint
    fileCache[file] = cache
  }

  private func append(
    _ bytes: Data.SubSequence,
    to buffer: inout Data,
    oversized: inout Bool
  ) {
    guard !oversized else { return }
    guard buffer.count + bytes.count <= Self.maxLineBytes else {
      buffer.removeAll(keepingCapacity: false)
      oversized = true
      return
    }
    buffer.append(contentsOf: bytes)
  }

  private func finishLine(
    _ buffer: inout Data,
    oversized: inout Bool,
    parser: any UsageLogParser,
    sourceID: String,
    cache: inout LogCache,
    metrics: inout MutableDiagnostics
  ) {
    if oversized {
      metrics.oversizedRecords += 1
    } else if !buffer.isEmpty {
      let result = parser.parse(
        buffer,
        sourceID: sourceID,
        state: &cache.parserState
      )
      merge(result, into: &cache, metrics: &metrics)
    }
    buffer.removeAll(keepingCapacity: true)
    oversized = false
  }

  private func merge(
    _ result: ParseResult,
    into cache: inout LogCache,
    metrics: inout MutableDiagnostics,
    countRejected: Bool = true
  ) {
    for event in result.events {
      cache.events[event.id] = event
    }
    if countRejected { metrics.rejectedRecords += result.rejectedRecords }
  }

  private func collectOpenCode(
    interval: DateInterval,
    metrics: inout MutableDiagnostics
  ) -> [UsageEvent] {
    guard let fingerprint = databaseFingerprint(locations.openCodeDatabase) else {
      databaseCache = nil
      return []
    }
    if let cache = databaseCache,
      cache.fingerprint == fingerprint,
      cache.interval == interval
    {
      return cache.events
    }

    do {
      let result = try OpenCodeDatabaseReader.read(
        locations.openCodeDatabase,
        interval: interval
      )
      metrics.databaseRowsRead += result.rowsRead
      metrics.rejectedRecords += result.rejectedRecords
      databaseCache = DatabaseCache(
        fingerprint: fingerprint,
        interval: interval,
        events: result.events
      )
      return result.events
    } catch {
      metrics.sourceErrors += 1
      return databaseCache?.events ?? []
    }
  }

  private func fingerprint(_ url: URL) throws -> FileFingerprint {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard
      let size = (attributes[.size] as? NSNumber)?.intValue,
      let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
    else { throw CollectorError.unreadableFile }
    return FileFingerprint(
      size: size,
      modified: attributes[.modificationDate] as? Date ?? .distantPast,
      inode: inode
    )
  }

  private func databaseFingerprint(_ url: URL) -> [FileFingerprint]? {
    guard let database = try? fingerprint(url) else { return nil }
    let walURL = URL(fileURLWithPath: url.path + "-wal")
    return [database, try? fingerprint(walURL)].compactMap { $0 }
  }
}

private struct JSONLSource: Sendable {
  let provider: AIProvider
  let directory: URL
  let parser: any UsageLogParser
}

private struct FileFingerprint: Equatable, Sendable {
  let size: Int
  let modified: Date
  let inode: UInt64
}

private struct LogCache: Sendable {
  var fingerprint: FileFingerprint?
  var offset: UInt64 = 0
  var tail = Data()
  var tailIsOversized = false
  var events: [String: UsageEvent] = [:]
  var parserState = UsageParserState()
}

private struct DatabaseCache: Sendable {
  let fingerprint: [FileFingerprint]
  let interval: DateInterval
  let events: [UsageEvent]
}

private struct MutableDiagnostics {
  var filesDiscovered = 0
  var filesRead = 0
  var bytesRead = 0
  var databaseRowsRead = 0
  var rejectedRecords = 0
  var oversizedRecords = 0
  var sourceErrors = 0

  func snapshot(elapsed: Duration) -> CollectionDiagnostics {
    CollectionDiagnostics(
      filesDiscovered: filesDiscovered,
      filesRead: filesRead,
      bytesRead: bytesRead,
      databaseRowsRead: databaseRowsRead,
      rejectedRecords: rejectedRecords,
      oversizedRecords: oversizedRecords,
      sourceErrors: sourceErrors,
      elapsed: elapsed
    )
  }
}

private enum CollectorError: Error {
  case unreadableFile
}
