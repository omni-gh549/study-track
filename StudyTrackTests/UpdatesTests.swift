import SwiftData
import XCTest
@testable import StudyTrack

private final class StubHTTP: UpdateHTTP {
    var releasesBody = Data("[]".utf8)
    var releasesStatus = 200
    var releasesHeaders: [String: String] = [:]
    var releasesError: Error?
    var downloadData = Data()
    var downloadStatus = 200
    private(set) var requests: [URLRequest] = []

    private func response(_ request: URLRequest, _ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let releasesError { throw releasesError }
        return (releasesBody, response(request, releasesStatus, releasesHeaders))
    }

    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        requests.append(request)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stub-\(UUID().uuidString).ipa")
        try downloadData.write(to: tmp)
        return (tmp, response(request, downloadStatus))
    }
}

private let zipMagic = Data([0x50, 0x4B, 0x03, 0x04])

private func releaseJSON(tag: String, draft: Bool = false, assets: String? = nil, body: String = "\"Notes\"") -> String {
    let defaultAssets = #"[{"id": 11, "name": "StudyTrack.ipa", "size": 104, "url": "https://api.github.com/repos/o/r/releases/assets/11", "state": "uploaded"}]"#
    return """
    {"id": \(abs(tag.hashValue % 100000)), "tag_name": "\(tag)", "name": "Release \(tag)", "body": \(body),
     "draft": \(draft), "prerelease": true, "published_at": "2026-10-17T10:28:59Z",
     "html_url": "https://github.com/o/r/releases/tag/\(tag)", "assets": \(assets ?? defaultAssets)}
    """
}

@MainActor
final class UpdatesTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("updates-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func service(_ http: StubHTTP, token: String? = "secret-token", build: Int = 5) -> UpdateService {
        UpdateService(http: http, tokenProvider: { token }, currentBuild: build, currentVersion: "0.1.0",
                      updatesDirectory: dir, repo: "o/r")
    }

    private func jsonList(_ items: [String]) -> Data { Data("[\(items.joined(separator: ","))]".utf8) }

    // MARK: Pure logic

    func testTagParsing() {
        XCTAssertEqual(UpdateLogic.parse(tag: "v0.5.0-build.10")?.build, 10)
        XCTAssertEqual(UpdateLogic.parse(tag: "v0.5.0-build.10")?.version, "0.5.0")
        XCTAssertEqual(UpdateLogic.parse(tag: "0.6.1-build.3")?.build, 3)
        XCTAssertNil(UpdateLogic.parse(tag: "v1.0.0"))
        XCTAssertNil(UpdateLogic.parse(tag: "v-build.4"))
        XCTAssertNil(UpdateLogic.parse(tag: "v1.0-build.x"))
        XCTAssertNil(UpdateLogic.parse(tag: "v1.0-build.0"))
        XCTAssertNil(UpdateLogic.parse(tag: ""))
    }

    func testReleasePickingIgnoresDraftsAndAssetlessAndGarbage() throws {
        let data = jsonList([
            releaseJSON(tag: "v0.9.0-build.40", draft: true),                          // draft
            releaseJSON(tag: "v0.8.0-build.30", assets: "[]"),                          // no assets
            releaseJSON(tag: "v0.8.0-build.31", assets: #"[{"id":1,"name":"notes.txt","size":1,"url":"https://x.invalid/1","state":"uploaded"}]"#),
            releaseJSON(tag: "nightly"),                                                // unparseable tag
            releaseJSON(tag: "v0.5.0-build.10", body: "null"),                          // null body is fine
            releaseJSON(tag: "v0.7.0-build.20"),
        ])
        let releases = try UpdateLogic.releases(fromJSON: data)
        XCTAssertEqual(Set(releases.map(\.build)), [10, 20])
        XCTAssertEqual(UpdateLogic.latest(in: releases)?.build, 20)
        XCTAssertEqual(releases.first { $0.build == 10 }?.notes, "")
        XCTAssertEqual(UpdateLogic.latest(in: releases)?.assetSize, 104)
        XCTAssertNil(UpdateLogic.latest(in: []))
    }

    func testIsNewer() throws {
        let r = try XCTUnwrap(UpdateLogic.releases(fromJSON: jsonList([releaseJSON(tag: "v1.0.0-build.7")])).first)
        XCTAssertTrue(UpdateLogic.isNewer(r, than: 6))
        XCTAssertFalse(UpdateLogic.isNewer(r, than: 7))
        XCTAssertFalse(UpdateLogic.isNewer(r, than: 8))
    }

    func testGarbageJSONThrows() {
        XCTAssertThrowsError(try UpdateLogic.releases(fromJSON: Data("nope".utf8)))
        XCTAssertThrowsError(try UpdateLogic.releases(fromJSON: Data("{}".utf8)))
    }

    // MARK: Checking

    func testNewerReleaseIsAvailableAndRequestIsAuthenticated() async {
        let http = StubHTTP()
        http.releasesBody = jsonList([releaseJSON(tag: "v0.7.0-build.20"), releaseJSON(tag: "v0.6.0-build.12")])
        let s = service(http)
        await s.check()
        guard case .available(let release) = s.status else { return XCTFail("status: \(s.status)") }
        XCTAssertEqual(release.build, 20)
        XCTAssertNotNil(s.lastChecked)
        let request = http.requests[0]
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertTrue(request.url!.absoluteString.contains("/repos/o/r/releases"))
    }

    func testSameOrOlderBuildIsUpToDate() async {
        let http = StubHTTP()
        http.releasesBody = jsonList([releaseJSON(tag: "v0.5.0-build.5")])
        let s = service(http, build: 5)
        await s.check()
        XCTAssertEqual(s.status, .upToDate)
        let newer = service(http, build: 9)
        await newer.check()
        XCTAssertEqual(newer.status, .upToDate)
    }

    func testNoReleasesIsUpToDate() async {
        let s = service(StubHTTP())
        await s.check()
        XCTAssertEqual(s.status, .upToDate)
    }

    func testMissingTokenNeverTouchesTheNetwork() async {
        let http = StubHTTP()
        let s = service(http, token: nil)
        XCTAssertFalse(s.hasToken)
        await s.check()
        XCTAssertEqual(s.status, .needsToken)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testHTTPErrorsBecomeHelpfulMessages() async {
        func failure(_ status: Int, headers: [String: String] = [:]) async -> String {
            let http = StubHTTP()
            http.releasesStatus = status
            http.releasesHeaders = headers
            let s = service(http)
            await s.check()
            guard case .failed(let message) = s.status else { return "NOT FAILED: \(s.status)" }
            return message
        }
        let unauthorized = await failure(401)
        let forbidden = await failure(403)
        let rateLimited = await failure(403, headers: ["x-ratelimit-remaining": "0"])
        let notFound = await failure(404)
        let server = await failure(500)
        XCTAssertTrue(unauthorized.contains("token"))
        XCTAssertTrue(forbidden.contains("token"))
        XCTAssertTrue(rateLimited.contains("rate"))
        XCTAssertTrue(notFound.contains("repository"))
        XCTAssertTrue(server.contains("500"))
    }

    func testOfflineMessage() async {
        let http = StubHTTP()
        http.releasesError = URLError(.notConnectedToInternet)
        let s = service(http)
        await s.check()
        guard case .failed(let message) = s.status else { return XCTFail() }
        XCTAssertTrue(message.contains("internet"))
    }

    func testBadJSONFromServerIsHandled() async {
        let http = StubHTTP()
        http.releasesBody = Data("<html>oops</html>".utf8)
        let s = service(http)
        await s.check()
        guard case .failed = s.status else { return XCTFail("status: \(s.status)") }
    }

    // MARK: Downloading

    private func availableRelease(_ s: UpdateService, _ http: StubHTTP) async throws -> ReleaseInfo {
        http.releasesBody = jsonList([releaseJSON(tag: "v0.7.0-build.20")])
        await s.check()
        guard case .available(let release) = s.status else { throw XCTSkip("not available: \(s.status)") }
        return release
    }

    func testDownloadSucceedsAndVerifies() async throws {
        let http = StubHTTP()
        http.downloadData = zipMagic + Data(repeating: 7, count: 100)   // 104 bytes, matches asset size
        let s = service(http)
        let release = try await availableRelease(s, http)
        await s.startDownload(release, context: nil)
        guard case .ready(let file) = s.download else { return XCTFail("download: \(s.download)") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(file.lastPathComponent, "StudyTrack-0.7.0-build20.ipa")
        let request = http.requests.last!
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/octet-stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/o/r/releases/assets/11")
    }

    func testDownloadWithWrongSizeIsRejectedAndDeleted() async throws {
        let http = StubHTTP()
        http.downloadData = zipMagic + Data(repeating: 1, count: 10)
        let s = service(http)
        let release = try await availableRelease(s, http)
        await s.startDownload(release, context: nil)
        guard case .failed(let message) = s.download else { return XCTFail("download: \(s.download)") }
        XCTAssertTrue(message.contains("damaged"))
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertTrue(leftovers.filter { $0.hasSuffix(".ipa") }.isEmpty)
    }

    func testDownloadThatIsNotAZipIsRejected() async throws {
        let http = StubHTTP()
        http.downloadData = Data(repeating: 0x41, count: 104)
        let s = service(http)
        let release = try await availableRelease(s, http)
        await s.startDownload(release, context: nil)
        guard case .failed = s.download else { return XCTFail("download: \(s.download)") }
    }

    func testDownloadHTTPErrorIsReported() async throws {
        let http = StubHTTP()
        let s = service(http)
        let release = try await availableRelease(s, http)
        http.downloadStatus = 404
        await s.startDownload(release, context: nil)
        guard case .failed(let message) = s.download else { return XCTFail() }
        XCTAssertTrue(message.contains("repository"))
    }

    func testDownloadWritesSafetyBackupFirst() async throws {
        let container = try ModelContainer(for: Persistence.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(Subject(name: "Maths"))
        try context.save()
        let before = (try? FileManager.default.contentsOfDirectory(atPath: AutoBackup.directory.path))?.count ?? 0

        let http = StubHTTP()
        http.downloadData = zipMagic + Data(repeating: 7, count: 100)
        let s = service(http)
        let release = try await availableRelease(s, http)
        await s.startDownload(release, context: context)

        let files = (try? FileManager.default.contentsOfDirectory(atPath: AutoBackup.directory.path)) ?? []
        XCTAssertGreaterThan(files.count, before)
        XCTAssertTrue(files.contains { $0.hasPrefix("pre-update") })
        for f in files where f.hasPrefix("pre-update") {
            try? FileManager.default.removeItem(at: AutoBackup.directory.appendingPathComponent(f))
        }
    }

    func testStaleInstallersAreCleanedUp() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = dir.appendingPathComponent("StudyTrack-0.4.0-build3.ipa")
        let current = dir.appendingPathComponent("StudyTrack-0.5.0-build5.ipa")
        let newer = dir.appendingPathComponent("StudyTrack-0.6.0-build8.ipa")
        for f in [old, current, newer] { try Data([1]).write(to: f) }
        _ = service(StubHTTP(), build: 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newer.path))
    }

    func testIPAValidator() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let good = dir.appendingPathComponent("good.ipa")
        try (zipMagic + Data(repeating: 0, count: 6)).write(to: good)
        XCTAssertTrue(UpdateService.looksLikeValidIPA(good, expectedSize: 10))
        XCTAssertFalse(UpdateService.looksLikeValidIPA(good, expectedSize: 11))
        XCTAssertTrue(UpdateService.looksLikeValidIPA(good, expectedSize: 0))
        let tiny = dir.appendingPathComponent("tiny.ipa")
        try Data([0x50]).write(to: tiny)
        XCTAssertFalse(UpdateService.looksLikeValidIPA(tiny, expectedSize: 0))
        XCTAssertFalse(UpdateService.looksLikeValidIPA(dir.appendingPathComponent("missing.ipa"), expectedSize: 0))
    }

    // MARK: Secrets

    func testSecretStoreRoundTrip() {
        let key = "test-\(UUID().uuidString)"
        defer { SecretStore.remove(key) }
        XCTAssertNil(SecretStore.get(key))
        SecretStore.set("one", for: key)
        XCTAssertEqual(SecretStore.get(key), "one")
        SecretStore.set("two", for: key)
        XCTAssertEqual(SecretStore.get(key), "two")
        SecretStore.remove(key)
        XCTAssertNil(SecretStore.get(key))
    }
}
