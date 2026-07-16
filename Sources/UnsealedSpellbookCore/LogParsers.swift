import Foundation

public struct ParseResult: Sendable {
  public let events: [UsageEvent]
  public let rejectedRecords: Int
  public let removedEventIDs: Set<String>

  public init(
    events: [UsageEvent],
    rejectedRecords: Int,
    removedEventIDs: Set<String> = []
  ) {
    self.events = events
    self.rejectedRecords = rejectedRecords
    self.removedEventIDs = removedEventIDs
  }
}

public struct UsageParserState: Sendable {
  var currentModel: ModelIdentity?
  var reasoningVariant: String?
  var seenEventIDs: Set<String> = []
  var geminiSessionID: String?
  var geminiLastUpdated: Date?
  var geminiMessageIDs: [String] = []
  var geminiMessageIDSet: Set<String> = []
  var geminiEventIDs: [String: String] = [:]

  public init() {}
}

public protocol UsageLogParser: Sendable {
  func parse(_ data: Data, sourceID: String, state: inout UsageParserState) -> ParseResult
}

extension UsageLogParser {
  public func parse(_ data: Data, sourceID: String) -> ParseResult {
    var state = UsageParserState()
    return parse(data, sourceID: sourceID, state: &state)
  }
}

public struct GeminiCLIParser: UsageLogParser {
  public init() {}

  public func parse(
    _ data: Data,
    sourceID: String,
    state: inout UsageParserState
  ) -> ParseResult {
    let records =
      JSONLog.object(from: data).map { ([$0], 0) }
      ?? JSONLog.records(in: data)
    var rejected = records.1
    var updated: [String: UsageEvent] = [:]
    var removed: Set<String> = []

    for record in records.0 {
      if let rewindID = record["$rewindTo"] as? String {
        rewind(
          to: rewindID,
          state: &state,
          updated: &updated,
          removed: &removed
        )
        continue
      }
      if record["id"] is String {
        apply(
          record,
          sourceID: sourceID,
          state: &state,
          updated: &updated,
          removed: &removed,
          rejected: &rejected
        )
        continue
      }
      if let values = record["$set"] as? [String: Any] {
        updateGeminiMetadata(from: values, state: &state)
        if values.keys.contains("messages") {
          apply(
            values["messages"],
            replacing: true,
            sourceID: sourceID,
            state: &state,
            updated: &updated,
            removed: &removed,
            rejected: &rejected
          )
        }
        continue
      }
      if let values = record["$push"] as? [String: Any] {
        apply(
          values["messages"],
          replacing: false,
          sourceID: sourceID,
          state: &state,
          updated: &updated,
          removed: &removed,
          rejected: &rejected
        )
        continue
      }
      if record["sessionId"] is String {
        updateGeminiMetadata(from: record, state: &state)
        if record.keys.contains("messages") {
          apply(
            record["messages"],
            replacing: false,
            sourceID: sourceID,
            state: &state,
            updated: &updated,
            removed: &removed,
            rejected: &rejected
          )
        }
      }
    }

    return ParseResult(
      events: state.geminiMessageIDs.compactMap {
        state.geminiEventIDs[$0].flatMap { updated[$0] }
      },
      rejectedRecords: rejected,
      removedEventIDs: removed
    )
  }

  private func updateGeminiMetadata(
    from record: [String: Any],
    state: inout UsageParserState
  ) {
    if let sessionID = record["sessionId"] as? String, !sessionID.isEmpty {
      state.geminiSessionID = sessionID
    }
    if let lastUpdated = JSONLog.date(record["lastUpdated"]) {
      state.geminiLastUpdated = lastUpdated
    }
  }

  private func apply(
    _ value: Any?,
    replacing: Bool,
    sourceID: String,
    state: inout UsageParserState,
    updated: inout [String: UsageEvent],
    removed: inout Set<String>,
    rejected: inout Int
  ) {
    if replacing {
      for eventID in state.geminiEventIDs.values {
        removed.insert(eventID)
        updated.removeValue(forKey: eventID)
      }
      state.geminiMessageIDs.removeAll()
      state.geminiMessageIDSet.removeAll()
      state.geminiEventIDs.removeAll()
    }

    let messages: [[String: Any]]
    if let message = value as? [String: Any] {
      messages = [message]
    } else if let values = value as? [Any] {
      messages = values.compactMap { $0 as? [String: Any] }
    } else {
      return
    }
    for message in messages {
      apply(
        message,
        sourceID: sourceID,
        state: &state,
        updated: &updated,
        removed: &removed,
        rejected: &rejected
      )
    }
  }

  private func apply(
    _ message: [String: Any],
    sourceID: String,
    state: inout UsageParserState,
    updated: inout [String: UsageEvent],
    removed: inout Set<String>,
    rejected: inout Int
  ) {
    guard let messageID = message["id"] as? String, !messageID.isEmpty else { return }
    if state.geminiMessageIDSet.insert(messageID).inserted {
      state.geminiMessageIDs.append(messageID)
    }

    guard message["type"] as? String == "gemini" else {
      removeUsage(
        for: messageID,
        state: &state,
        updated: &updated,
        removed: &removed
      )
      return
    }
    guard
      let timestamp = JSONLog.date(message["timestamp"]),
      let tokens = message["tokens"] as? [String: Any],
      let rawInput = JSONLog.token(tokens["input"]),
      let output = JSONLog.token(tokens["output"]),
      let cached = JSONLog.token(tokens["cached"], default: 0),
      let thoughts = JSONLog.token(tokens["thoughts"], default: 0),
      let tool = JSONLog.token(tokens["tool"], default: 0),
      cached <= rawInput,
      !tokens.keys.contains("total") || JSONLog.token(tokens["total"]) != nil,
      let usage = geminiUsage(
        rawInput: rawInput,
        output: output,
        cached: cached,
        thoughts: thoughts,
        tool: tool,
        reportedTotal: JSONLog.token(tokens["total"])
      )
    else {
      removeUsage(
        for: messageID,
        state: &state,
        updated: &updated,
        removed: &removed
      )
      rejected += 1
      return
    }

    let sessionID = state.geminiSessionID ?? sourceID
    let eventID = "\(sessionID):\(messageID)"
    if let previousID = state.geminiEventIDs[messageID], previousID != eventID {
      removed.insert(previousID)
      updated.removeValue(forKey: previousID)
    }
    state.geminiEventIDs[messageID] = eventID
    removed.remove(eventID)
    updated[eventID] = UsageEvent(
      id: eventID,
      provider: .geminiCLI,
      timestamp: timestamp,
      usage: usage,
      model: (message["model"] as? String).map {
        ModelIdentity(tool: .geminiCLI, name: $0)
      } ?? .unknown(tool: .geminiCLI)
    )
  }

  private func rewind(
    to messageID: String,
    state: inout UsageParserState,
    updated: inout [String: UsageEvent],
    removed: inout Set<String>
  ) {
    let start =
      state.geminiMessageIDs.firstIndex(of: messageID) ?? state.geminiMessageIDs.startIndex
    let discarded = state.geminiMessageIDs[start...]
    for discardedID in discarded {
      state.geminiMessageIDSet.remove(discardedID)
      if let eventID = state.geminiEventIDs.removeValue(forKey: discardedID) {
        removed.insert(eventID)
        updated.removeValue(forKey: eventID)
      }
    }
    state.geminiMessageIDs.removeSubrange(start...)
  }

  private func removeUsage(
    for messageID: String,
    state: inout UsageParserState,
    updated: inout [String: UsageEvent],
    removed: inout Set<String>
  ) {
    guard let eventID = state.geminiEventIDs.removeValue(forKey: messageID) else { return }
    removed.insert(eventID)
    updated.removeValue(forKey: eventID)
  }

  private func sum(_ lhs: Int, _ rhs: Int) -> Int? {
    let (value, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? nil : value
  }

  private func geminiUsage(
    rawInput: Int,
    output: Int,
    cached: Int,
    thoughts: Int,
    tool: Int,
    reportedTotal: Int?
  ) -> TokenUsage? {
    guard
      let promptAndOutput = sum(rawInput, output),
      let baseTotal = sum(promptAndOutput, thoughts)
    else { return nil }

    let separateToolTokens: Int
    let total: Int
    if let reportedTotal {
      if reportedTotal == baseTotal {
        separateToolTokens = 0
        total = reportedTotal
      } else if let totalWithTool = sum(baseTotal, tool), reportedTotal == totalWithTool {
        separateToolTokens = tool
        total = reportedTotal
      } else {
        return nil
      }
    } else {
      guard tool == 0 else { return nil }
      separateToolTokens = 0
      total = baseTotal
    }

    guard let input = sum(rawInput - cached, separateToolTokens) else { return nil }
    return TokenUsage(
      input: input,
      output: output,
      cacheRead: cached,
      reasoning: thoughts,
      total: total
    )
  }
}

public struct ClaudeCodeParser: UsageLogParser {
  public init() {}

  public func parse(
    _ data: Data,
    sourceID: String,
    state: inout UsageParserState
  ) -> ParseResult {
    let records = JSONLog.records(in: data)
    var rejected = records.rejected
    var order: [String] = []
    var latest: [String: UsageEvent] = [:]

    for record in records.values {
      guard record["type"] as? String == "assistant" else { continue }
      guard
        let sessionID = record["sessionId"] as? String,
        let timestamp = JSONLog.date(record["timestamp"]),
        let message = record["message"] as? [String: Any],
        let messageID = message["id"] as? String,
        let usage = message["usage"] as? [String: Any],
        let input = JSONLog.token(usage["input_tokens"]),
        let output = JSONLog.token(usage["output_tokens"]),
        let cacheRead = JSONLog.token(usage["cache_read_input_tokens"], default: 0),
        let cacheWrite = JSONLog.token(usage["cache_creation_input_tokens"], default: 0)
      else {
        rejected += 1
        continue
      }

      let id = "\(sessionID):\(messageID)"
      if latest[id] == nil { order.append(id) }
      let model =
        (message["model"] as? String).map {
          ModelIdentity(tool: .claudeCode, name: $0)
        } ?? .unknown(tool: .claudeCode)
      latest[id] = UsageEvent(
        id: id,
        provider: .claudeCode,
        timestamp: timestamp,
        usage: TokenUsage(
          input: input,
          output: output,
          cacheRead: cacheRead,
          cacheWrite: cacheWrite,
          total: input + output + cacheRead + cacheWrite
        ),
        model: model
      )
    }

    return ParseResult(events: order.compactMap { latest[$0] }, rejectedRecords: rejected)
  }
}

public struct CodexParser: UsageLogParser {
  public init() {}

  public func parse(
    _ data: Data,
    sourceID: String,
    state: inout UsageParserState
  ) -> ParseResult {
    let records = JSONLog.records(in: data)
    var rejected = records.rejected
    var events: [UsageEvent] = []

    for record in records.values {
      guard let payload = record["payload"] as? [String: Any] else { continue }
      let recordType = record["type"] as? String
      let payloadType = payload["type"] as? String

      if recordType == "turn_context" {
        state.currentModel = model(
          name: payload["model"],
          variant: payload["effort"]
        )
        continue
      }

      if recordType == "event_msg", payloadType == "thread_settings_applied" {
        let settings = payload["thread_settings"] as? [String: Any]
        state.currentModel = model(
          name: settings?["model"],
          variant: settings?["reasoning_effort"]
        )
        continue
      }

      guard recordType == "event_msg", payloadType == "token_count" else { continue }
      guard payload["info"] is [String: Any] else { continue }
      guard
        let timestamp = JSONLog.date(record["timestamp"]),
        let info = payload["info"] as? [String: Any],
        let last = codexUsage(info["last_token_usage"]),
        let cumulative = codexUsage(info["total_token_usage"])
      else {
        rejected += 1
        continue
      }

      // ponytail: verified Codex 0.144.1 totals never decrease; add fork lineage only when a decreasing fixture exists.
      let id = [
        sourceID,
        String(cumulative.input),
        String(cumulative.output),
        String(cumulative.cacheRead),
        String(cumulative.reasoning),
        String(cumulative.total),
      ].joined(separator: ":")
      guard state.seenEventIDs.insert(id).inserted else { continue }
      events.append(
        UsageEvent(
          id: id,
          provider: .codex,
          timestamp: timestamp,
          usage: last,
          model: state.currentModel ?? .unknown(tool: .codex)
        ))
    }

    return ParseResult(events: events, rejectedRecords: rejected)
  }

  private func model(name: Any?, variant: Any?) -> ModelIdentity? {
    guard let name = name as? String else { return nil }
    return ModelIdentity(tool: .codex, name: name, variant: variant as? String)
  }

  private func codexUsage(_ value: Any?) -> TokenUsage? {
    guard
      let usage = value as? [String: Any],
      let rawInput = JSONLog.token(usage["input_tokens"]),
      let cached = JSONLog.token(usage["cached_input_tokens"], default: 0),
      let output = JSONLog.token(usage["output_tokens"]),
      let reasoning = JSONLog.token(usage["reasoning_output_tokens"], default: 0),
      let total = JSONLog.token(usage["total_tokens"]),
      cached <= rawInput,
      reasoning <= output,
      total == rawInput + output
    else { return nil }

    return TokenUsage(
      input: rawInput - cached,
      output: output - reasoning,
      cacheRead: cached,
      reasoning: reasoning,
      total: total
    )
  }
}

public struct OpenCodeParser: UsageLogParser {
  public init() {}

  public func parse(
    _ data: Data,
    sourceID: String,
    state: inout UsageParserState
  ) -> ParseResult {
    guard let record = JSONLog.object(from: data) else {
      return ParseResult(events: [], rejectedRecords: 1)
    }
    guard record["role"] as? String == "assistant" else {
      return ParseResult(events: [], rejectedRecords: 0)
    }
    guard
      let timestamp = JSONLog.date((record["time"] as? [String: Any])?["created"]),
      let tokens = record["tokens"] as? [String: Any],
      let input = JSONLog.token(tokens["input"]),
      let output = JSONLog.token(tokens["output"]),
      let reasoning = JSONLog.token(tokens["reasoning"], default: 0),
      let cache = tokens["cache"] as? [String: Any],
      let cacheRead = JSONLog.token(cache["read"], default: 0),
      let cacheWrite = JSONLog.token(cache["write"], default: 0)
    else {
      return ParseResult(events: [], rejectedRecords: 1)
    }

    let calculatedTotal = input + output + reasoning + cacheRead + cacheWrite
    if let reportedTotal = JSONLog.token(tokens["total"]), reportedTotal != calculatedTotal {
      return ParseResult(events: [], rejectedRecords: 1)
    }
    let id = (record["id"] as? String) ?? sourceID
    let model =
      (record["modelID"] as? String).map {
        ModelIdentity(
          tool: .openCode,
          backend: record["providerID"] as? String,
          name: $0,
          variant: record["variant"] as? String
        )
      } ?? .unknown(tool: .openCode)
    return ParseResult(
      events: [
        UsageEvent(
          id: id,
          provider: .openCode,
          timestamp: timestamp,
          usage: TokenUsage(
            input: input,
            output: output,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            reasoning: reasoning,
            total: calculatedTotal
          ),
          model: model
        )
      ],
      rejectedRecords: 0
    )
  }
}

public struct OhMyPiParser: UsageLogParser {
  public init() {}

  public func parse(
    _ data: Data,
    sourceID: String,
    state: inout UsageParserState
  ) -> ParseResult {
    let records = JSONLog.records(in: data)
    var rejected = records.rejected
    var order: [String] = []
    var latest: [String: UsageEvent] = [:]

    for record in records.values {
      let type = record["type"] as? String
      if type == "thinking_level_change" {
        state.reasoningVariant = record["thinkingLevel"] as? String
        continue
      }
      guard type == "message" else { continue }
      guard
        let recordID = record["id"] as? String,
        let timestamp = JSONLog.date(record["timestamp"]),
        let message = record["message"] as? [String: Any],
        message["role"] as? String == "assistant",
        let usage = message["usage"] as? [String: Any],
        let input = JSONLog.token(usage["input"]),
        let output = JSONLog.token(usage["output"]),
        let cacheRead = JSONLog.token(usage["cacheRead"], default: 0),
        let cacheWrite = JSONLog.token(usage["cacheWrite"], default: 0),
        let reasoning = JSONLog.token(usage["reasoningTokens"], default: 0),
        let total = JSONLog.token(usage["totalTokens"]),
        reasoning <= output,
        total == input + output + cacheRead + cacheWrite
      else {
        rejected += 1
        continue
      }

      let id = "\(sourceID):\(recordID)"
      if latest[id] == nil { order.append(id) }
      let model =
        (message["model"] as? String).map {
          ModelIdentity(
            tool: .ohMyPi,
            backend: message["provider"] as? String,
            name: $0,
            variant: state.reasoningVariant
          )
        } ?? .unknown(tool: .ohMyPi)
      latest[id] = UsageEvent(
        id: id,
        provider: .ohMyPi,
        timestamp: timestamp,
        usage: TokenUsage(
          input: input,
          output: output - reasoning,
          cacheRead: cacheRead,
          cacheWrite: cacheWrite,
          reasoning: reasoning,
          total: total
        ),
        model: model
      )
    }
    return ParseResult(events: order.compactMap { latest[$0] }, rejectedRecords: rejected)
  }
}

private enum JSONLog {
  static func records(in data: Data) -> (values: [[String: Any]], rejected: Int) {
    var values: [[String: Any]] = []
    var rejected = 0

    for line in data.split(separator: 0x0A) {
      if let object = object(from: Data(line)) {
        values.append(object)
      } else {
        rejected += 1
      }
    }
    return (values, rejected)
  }

  static func object(from data: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  static func token(_ value: Any?, default defaultValue: Int? = nil) -> Int? {
    guard let value else { return defaultValue }
    let number: Int?
    if let integer = value as? Int {
      number = integer
    } else if let integer = value as? Int64 {
      number = Int(exactly: integer)
    } else {
      number = nil
    }
    guard let number, number >= 0 else { return nil }
    return number
  }

  static func date(_ value: Any?) -> Date? {
    if let milliseconds = token(value) {
      let seconds =
        milliseconds > 10_000_000_000 ? Double(milliseconds) / 1_000 : Double(milliseconds)
      return Date(timeIntervalSince1970: seconds)
    }
    guard let string = value as? String else { return nil }
    if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
      return date
    }
    return try? Date.ISO8601FormatStyle().parse(string)
  }
}
