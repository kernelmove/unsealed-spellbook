import Foundation
import Observation

enum GitHubReleaseCheckError: Error, Equatable {
  case invalidHTTPResponse
  case unsuccessfulStatusCode(Int)
  case invalidPayload
  case invalidVersion(String)
}

struct ReleaseVersion: Comparable, Sendable {
  let major: Int
  let minor: Int
  let patch: Int

  init(_ major: Int, _ minor: Int, _ patch: Int) {
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  init(parsing rawValue: String) throws {
    var normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.first == "v" {
      normalized.removeFirst()
    }

    let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count == 2 || components.count == 3 else {
      throw GitHubReleaseCheckError.invalidVersion(rawValue)
    }

    let numbers = try components.map { component in
      guard
        !component.isEmpty,
        component.utf8.allSatisfy({ (48...57).contains($0) }),
        let number = Int(component)
      else {
        throw GitHubReleaseCheckError.invalidVersion(rawValue)
      }
      return number
    }

    self.init(numbers[0], numbers[1], numbers.count == 3 ? numbers[2] : 0)
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    return lhs.patch < rhs.patch
  }
}

struct GitHubReleaseStatus: Equatable, Sendable {
  let latestTag: String
  let isUpdateAvailable: Bool

  var releasePageURL: URL {
    GitHubReleaseChecker.latestReleasePageURL
  }
}

struct GitHubReleaseChecker: Sendable {
  typealias DataLoader = @Sendable (URL) async throws -> (Data, URLResponse)

  static let latestReleaseAPIURL = URL(
    string: "https://api.github.com/repos/kernelmove/unsealed-spellbook/releases/latest"
  )!
  static let latestReleasePageURL = URL(
    string: "https://github.com/kernelmove/unsealed-spellbook/releases/latest"
  )!

  private struct Response: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
      case tagName = "tag_name"
    }
  }

  private let dataLoader: DataLoader

  init(
    dataLoader: @escaping DataLoader = { url in
      var request = URLRequest(url: url)
      request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
      request.setValue("UnsealedSpellbook", forHTTPHeaderField: "User-Agent")
      request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
      return try await URLSession.shared.data(for: request)
    }
  ) {
    self.dataLoader = dataLoader
  }

  func check(currentVersion: String) async throws -> GitHubReleaseStatus {
    let current = try ReleaseVersion(parsing: currentVersion)
    let (data, response) = try await dataLoader(Self.latestReleaseAPIURL)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw GitHubReleaseCheckError.invalidHTTPResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw GitHubReleaseCheckError.unsuccessfulStatusCode(httpResponse.statusCode)
    }
    guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
      throw GitHubReleaseCheckError.invalidPayload
    }

    let latest = try ReleaseVersion(parsing: payload.tagName)
    return GitHubReleaseStatus(
      latestTag: payload.tagName,
      isUpdateAvailable: latest > current
    )
  }
}

enum GitHubReleaseState: Equatable {
  case idle
  case checking
  case upToDate(String)
  case updateAvailable(String)
  case failed
}

@MainActor
@Observable
final class GitHubReleaseStore {
  private(set) var state = GitHubReleaseState.idle
  let currentVersion: String
  let releasePageURL = GitHubReleaseChecker.latestReleasePageURL

  private let checker: GitHubReleaseChecker

  init(
    currentVersion: String = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "1.0.1",
    checker: GitHubReleaseChecker = GitHubReleaseChecker()
  ) {
    self.currentVersion = currentVersion
    self.checker = checker
  }

  func check() async {
    guard state != .checking else { return }
    state = .checking
    do {
      let status = try await checker.check(currentVersion: currentVersion)
      state =
        status.isUpdateAvailable
        ? .updateAvailable(status.latestTag)
        : .upToDate(status.latestTag)
    } catch {
      state = .failed
    }
  }
}
