import Foundation
import Testing

@testable import UnsealedSpellbook

@Suite("GitHub release checking")
struct GitHubReleaseCheckerTests {
  @Test("Release versions support a v prefix, an omitted patch, and numeric ordering")
  func releaseVersionParsing() throws {
    #expect(try ReleaseVersion(parsing: "v1.2.3") == ReleaseVersion(1, 2, 3))
    #expect(try ReleaseVersion(parsing: "1.2") == ReleaseVersion(1, 2, 0))
    #expect(try ReleaseVersion(parsing: "1.10.0") > ReleaseVersion(1, 9, 9))
  }

  @Test(
    "Malformed release versions fail explicitly",
    arguments: ["", "1", "1.two.3", "1.2.3.4", "1.2.3-beta"])
  func malformedReleaseVersion(rawValue: String) {
    #expect(throws: GitHubReleaseCheckError.invalidVersion(rawValue)) {
      try ReleaseVersion(parsing: rawValue)
    }
  }

  @Test("A newer GitHub tag is reported with the fixed trusted release page")
  func newerRelease() async throws {
    let checker = GitHubReleaseChecker { url in
      #expect(url == GitHubReleaseChecker.latestReleaseAPIURL)
      let payload = Data(
        #"{"tag_name":"v1.2.0","html_url":"https://attacker.invalid/release","assets":[{"browser_download_url":"https://attacker.invalid/app.dmg"}]}"#
          .utf8
      )
      return (payload, try httpResponse(url: url, statusCode: 200))
    }

    let status = try await checker.check(currentVersion: "1.1.9")

    #expect(status.latestTag == "v1.2.0")
    #expect(status.isUpdateAvailable)
    #expect(status.releasePageURL == GitHubReleaseChecker.latestReleasePageURL)
    #expect(
      status.releasePageURL.absoluteString
        == "https://github.com/kernelmove/unsealed-spellbook/releases/latest")
  }

  @Test("Equivalent or older GitHub tags do not report an update")
  func noNewerRelease() async throws {
    let equivalent = GitHubReleaseChecker { url in
      (Data(#"{"tag_name":"v1.2"}"#.utf8), try httpResponse(url: url, statusCode: 200))
    }
    let older = GitHubReleaseChecker { url in
      (Data(#"{"tag_name":"1.1.9"}"#.utf8), try httpResponse(url: url, statusCode: 200))
    }

    #expect(try await !equivalent.check(currentVersion: "1.2.0").isUpdateAvailable)
    #expect(try await !older.check(currentVersion: "1.2.0").isUpdateAvailable)
  }

  @Test("Non-success HTTP responses fail before decoding")
  func unsuccessfulHTTPStatus() async {
    let checker = GitHubReleaseChecker { url in
      (Data(#"{"tag_name":"9.0.0"}"#.utf8), try httpResponse(url: url, statusCode: 503))
    }

    await #expect(throws: GitHubReleaseCheckError.unsuccessfulStatusCode(503)) {
      try await checker.check(currentVersion: "1.0.0")
    }
  }

  @Test("Missing or malformed tag payloads fail explicitly", arguments: ["{}", #"{"tag_name":7}"#])
  func malformedPayload(json: String) async {
    let checker = GitHubReleaseChecker { url in
      (Data(json.utf8), try httpResponse(url: url, statusCode: 200))
    }

    await #expect(throws: GitHubReleaseCheckError.invalidPayload) {
      try await checker.check(currentVersion: "1.0.0")
    }
  }

  @Test("Non-HTTP responses and malformed decoded tags fail explicitly")
  func invalidResponseAndTag() async {
    let nonHTTP = GitHubReleaseChecker { url in
      (
        Data(),
        URLResponse(
          url: url,
          mimeType: "application/json",
          expectedContentLength: 0,
          textEncodingName: nil
        )
      )
    }
    let malformedTag = GitHubReleaseChecker { url in
      (Data(#"{"tag_name":"v1.beta"}"#.utf8), try httpResponse(url: url, statusCode: 200))
    }

    await #expect(throws: GitHubReleaseCheckError.invalidHTTPResponse) {
      try await nonHTTP.check(currentVersion: "1.0.0")
    }
    await #expect(throws: GitHubReleaseCheckError.invalidVersion("v1.beta")) {
      try await malformedTag.check(currentVersion: "1.0.0")
    }
  }

  @Test("The update store exposes manual-check states without downloading a release")
  @MainActor
  func updateStoreStates() async throws {
    let checker = GitHubReleaseChecker { url in
      (
        Data(#"{"tag_name":"v1.1.0"}"#.utf8),
        try httpResponse(url: url, statusCode: 200)
      )
    }
    let store = GitHubReleaseStore(currentVersion: "1.0.0", checker: checker)

    #expect(store.state == .idle)
    await store.check()

    #expect(store.state == .updateAvailable("v1.1.0"))
    #expect(store.releasePageURL == GitHubReleaseChecker.latestReleasePageURL)
  }

  @Test("Automatic checks are opt-in by preference and limited to once per day")
  func automaticCheckSchedule() throws {
    let suite = "GitHubReleaseCheckerTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    #expect(AppPreferences.shouldAutomaticallyCheckForUpdates(now: now, defaults: defaults))
    #expect(AppPreferences.automaticUpdateCheckDelay(now: now, defaults: defaults) == 0)

    AppPreferences.recordUpdateCheck(at: now.addingTimeInterval(-23 * 60 * 60), defaults: defaults)
    #expect(!AppPreferences.shouldAutomaticallyCheckForUpdates(now: now, defaults: defaults))
    #expect(
      try #require(AppPreferences.automaticUpdateCheckDelay(now: now, defaults: defaults))
        == 3_600.0
    )

    AppPreferences.recordUpdateCheck(at: now.addingTimeInterval(-25 * 60 * 60), defaults: defaults)
    #expect(AppPreferences.shouldAutomaticallyCheckForUpdates(now: now, defaults: defaults))

    defaults.set(false, forKey: AppPreferences.automaticallyCheckForUpdatesKey)
    #expect(!AppPreferences.shouldAutomaticallyCheckForUpdates(now: now, defaults: defaults))
    #expect(AppPreferences.automaticUpdateCheckDelay(now: now, defaults: defaults) == nil)
  }
}

private func httpResponse(url: URL, statusCode: Int) throws -> HTTPURLResponse {
  try #require(
    HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )
  )
}
