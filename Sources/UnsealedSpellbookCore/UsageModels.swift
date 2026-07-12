import Foundation

public enum AIProvider: String, CaseIterable, Sendable {
  case claudeCode
  case codex
  case ohMyPi
  case openCode
}

public struct TokenUsage: Equatable, Sendable {
  public let input: Int
  public let output: Int
  public let cacheRead: Int
  public let cacheWrite: Int
  public let reasoning: Int
  public let total: Int

  public init(
    input: Int,
    output: Int,
    cacheRead: Int = 0,
    cacheWrite: Int = 0,
    reasoning: Int = 0,
    total: Int
  ) {
    self.input = input
    self.output = output
    self.cacheRead = cacheRead
    self.cacheWrite = cacheWrite
    self.reasoning = reasoning
    self.total = total
  }

  public static let zero = TokenUsage(input: 0, output: 0, total: 0)

  public var cacheHitRate: Double {
    let allInput = input + cacheRead + cacheWrite
    return allInput == 0 ? 0 : Double(cacheRead) / Double(allInput)
  }

  static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
    TokenUsage(
      input: lhs.input + rhs.input,
      output: lhs.output + rhs.output,
      cacheRead: lhs.cacheRead + rhs.cacheRead,
      cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
      reasoning: lhs.reasoning + rhs.reasoning,
      total: lhs.total + rhs.total
    )
  }
}

public struct ModelIdentity: Hashable, Sendable {
  public let tool: AIProvider?
  public let backend: String?
  public let name: String
  public let variant: String?

  public init(
    tool: AIProvider? = nil,
    backend: String? = nil,
    name: String,
    variant: String? = nil
  ) {
    self.tool = tool
    self.backend = backend?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    self.name = name
    self.variant = variant?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }

  public static let unknown = ModelIdentity(name: "未知模型")

  public static func unknown(tool: AIProvider) -> ModelIdentity {
    ModelIdentity(tool: tool, name: "未知模型")
  }

  public var displayName: String {
    guard let variant else { return name }
    return "\(name) · \(variant)"
  }

  public var isKnown: Bool { name != "未知模型" }
}

public struct UsageEvent: Equatable, Sendable {
  public let id: String
  public let provider: AIProvider
  public let timestamp: Date
  public let usage: TokenUsage
  public let model: ModelIdentity

  public init(
    id: String,
    provider: AIProvider,
    timestamp: Date,
    usage: TokenUsage,
    model: ModelIdentity? = nil
  ) {
    self.id = id
    self.provider = provider
    self.timestamp = timestamp
    self.usage = usage
    self.model = model ?? .unknown(tool: provider)
  }
}

public struct UsageSnapshot: Equatable, Sendable {
  public let interval: DateInterval
  public let providers: [AIProvider: TokenUsage]
  public let total: TokenUsage
  public let eventCount: Int
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
