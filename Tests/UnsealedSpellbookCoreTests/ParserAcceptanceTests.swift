import Foundation
import Testing

@testable import UnsealedSpellbookCore

@Suite("Local AI usage parsing")
struct ParserAcceptanceTests {
  @Test("Claude usage is normalized and duplicate message IDs are counted once")
  func claudeUsage() throws {
    let partial =
      #"{"type":"assistant","sessionId":"session_1","timestamp":"2026-07-12T01:02:02.000Z","message":{"id":"msg_1","model":"claude-sonnet","usage":{"input_tokens":12,"output_tokens":1,"cache_read_input_tokens":20,"cache_creation_input_tokens":3}}}"#
    let final =
      #"{"type":"assistant","sessionId":"session_1","timestamp":"2026-07-12T01:02:03.000Z","message":{"id":"msg_1","model":"claude-sonnet","usage":{"input_tokens":12,"output_tokens":5,"cache_read_input_tokens":20,"cache_creation_input_tokens":3}}}"#
    let data = Data("\(partial)\n\(final)\nnot-json\n".utf8)

    let result = ClaudeCodeParser().parse(data, sourceID: "fixture")

    #expect(result.rejectedRecords == 1)
    #expect(result.events.count == 1)
    #expect(
      result.events.first?.usage
        == TokenUsage(
          input: 12,
          output: 5,
          cacheRead: 20,
          cacheWrite: 3,
          reasoning: 0,
          total: 40
        ))
    #expect(result.events.first?.model == ModelIdentity(tool: .claudeCode, name: "claude-sonnet"))
  }

  @Test("Codex cached input and reasoning subsets are not double counted")
  func codexUsage() {
    let context =
      #"{"timestamp":"2026-07-12T01:02:02Z","type":"turn_context","payload":{"model":"gpt-test","effort":"xhigh"}}"#
    let usage =
      #"{"timestamp":"2026-07-12T01:02:03Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":120,"cached_input_tokens":100,"output_tokens":30,"reasoning_output_tokens":10,"total_tokens":150},"total_token_usage":{"input_tokens":120,"cached_input_tokens":100,"output_tokens":30,"reasoning_output_tokens":10,"total_tokens":150}}}}"#
    let result = CodexParser().parse(Data("\(context)\n\(usage)".utf8), sourceID: "fixture")

    #expect(result.rejectedRecords == 0)
    #expect(
      result.events.first?.usage
        == TokenUsage(
          input: 20,
          output: 30,
          cacheRead: 100,
          cacheWrite: 0,
          reasoning: 10,
          total: 150
        ))
    #expect(
      result.events.first?.model
        == ModelIdentity(
          tool: .codex,
          name: "gpt-test",
          variant: "xhigh"
        ))
  }

  @Test("Codex never backfills a future model context")
  func codexContextOrdering() {
    let before =
      #"{"timestamp":"2026-07-12T01:02:01Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":15},"total_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":15}}}}"#
    let context =
      #"{"timestamp":"2026-07-12T01:02:02Z","type":"turn_context","payload":{"model":"gpt-test","effort":"medium"}}"#
    let after =
      #"{"timestamp":"2026-07-12T01:02:03Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":30},"total_token_usage":{"input_tokens":30,"cached_input_tokens":0,"output_tokens":15,"reasoning_output_tokens":0,"total_tokens":45}}}}"#

    let result = CodexParser().parse(
      Data("\(before)\n\(context)\n\(after)".utf8),
      sourceID: "fixture"
    )

    #expect(result.events.map(\.model.displayName) == ["未知模型", "gpt-test · medium"])
  }

  @Test("OpenCode message usage preserves its reported total")
  func openCodeUsage() {
    let data = Data(
      #"{"id":"msg_1","role":"assistant","time":{"created":1783827723000},"providerID":"openai","modelID":"gpt-test","variant":"high","tokens":{"input":8,"output":4,"reasoning":2,"cache":{"read":10,"write":1}}}"#
        .utf8
    )

    let result = OpenCodeParser().parse(data, sourceID: "fixture")

    #expect(result.rejectedRecords == 0)
    #expect(
      result.events.first?.usage
        == TokenUsage(
          input: 8,
          output: 4,
          cacheRead: 10,
          cacheWrite: 1,
          reasoning: 2,
          total: 25
        ))
    #expect(
      result.events.first?.model
        == ModelIdentity(
          tool: .openCode,
          backend: "openai",
          name: "gpt-test",
          variant: "high"
        ))
  }

  @Test("Oh My Pi reasoning is an output subset")
  func ohMyPiUsage() {
    let level = #"{"type":"thinking_level_change","thinkingLevel":"high"}"#
    let message =
      #"{"type":"message","id":"message_1","timestamp":"2026-07-12T01:02:03Z","message":{"role":"assistant","provider":"openai","model":"gpt-test","usage":{"input":8,"output":6,"cacheRead":10,"cacheWrite":1,"reasoningTokens":2,"totalTokens":25}}}"#
    let result = OhMyPiParser().parse(
      Data("\(level)\n\(message)".utf8),
      sourceID: "session_1"
    )

    #expect(result.rejectedRecords == 0)
    #expect(
      result.events.first?.usage
        == TokenUsage(
          input: 8,
          output: 6,
          cacheRead: 10,
          cacheWrite: 1,
          reasoning: 2,
          total: 25
        ))
    #expect(
      result.events.first?.model
        == ModelIdentity(
          tool: .ohMyPi,
          backend: "openai",
          name: "gpt-test",
          variant: "high"
        ))
  }
}
