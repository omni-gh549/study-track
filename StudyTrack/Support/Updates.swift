import Foundation
import SwiftData
import SwiftUI

// MARK: - Model

struct ReleaseInfo: Equatable, Identifiable {
    let id: Int
    let tag: String
    let version: String
    let build: Int
    let name: String
    let notes: String
    let publishedAt: Date?
    let assetURL: URL
    let assetName: String
    let assetSize: Int
    let pageURL: URL?
}

enum UpdateError: LocalizedError, Equatable {
    case unauthorized, notFound, rateLimited, server(Int), badResponse, corruptDownload

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "GitHub rejected the token. Check that it's valid and has read access to the repository."
        case .notFound: return "Couldn't find the repository. The token needs access to it (Contents: read-only)."
        case .rateLimited: return "GitHub is rate limiting requests. Try again in a little while."
        case .server(let code): return "GitHub returned an error (\(code)). Try again later."
        case .badResponse: return "GitHub sent an unexpected response."
        case .corruptDownload: return "The downloaded file looks damaged, so it was discarded. Try again."
        }
    }
}

// MARK: - Parsing & selection (pure, unit tested)

enum UpdateLogic {
    private struct GHRelease: Decodable {
        let id: Int
        let tagName: String
        let name: String?
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let publishedAt: Date?
        let htmlUrl: URL?
        let assets: [GHAsset]
    }

    private struct GHAsset: Decodable {
        let id: Int
        let name: String
        let size: Int
        let url: URL
        let state: String?
    }

    /// "v0.5.0-build.10" → ("0.5.0", 10)
    static func parse(tag: String) -> (version: String, build: Int)? {
        var t = tag.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        guard let range = t.range(of: "-build.") else { return nil }
        let version = String(t[..<range.lowerBound])
        guard !version.isEmpty, let build = Int(t[range.upperBound...]), build > 0 else { return nil }
        return (version, build)
    }

    /// Drafts, releases without an uploaded .ipa, and tags we can't understand are skipped.
    static func releases(fromJSON data: Data) throws -> [ReleaseInfo] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let raw = try decoder.decode([GHRelease].self, from: data)

        return raw.compactMap { release in
            guard !release.draft,
                  let parsed = parse(tag: release.tagName),
                  let asset = release.assets.first(where: {
                      $0.name.lowercased().hasSuffix(".ipa") && ($0.state ?? "uploaded") == "uploaded"
                  }) else { return nil }
            return ReleaseInfo(id: release.id, tag: release.tagName, version: parsed.version, build: parsed.build,
                               name: release.name ?? release.tagName, notes: release.body ?? "",
                               publishedAt: release.publishedAt, assetURL: asset.url, assetName: asset.name,
                               assetSize: asset.size, pageURL: release.htmlUrl)
        }
    }

    static func latest(in releases: [ReleaseInfo]) -> ReleaseInfo? {
        releases.max { $0.build < $1.build }
    }

    static func isNewer(_ release: ReleaseInfo, than currentBuild: Int) -> Bool {
        release.build > currentBuild
    }
}

// MARK: - HTTP (swappable for tests)

protocol UpdateHTTP {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Returns a temporary file with the body.
    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse)
}

/// GitHub redirects asset downloads to a signed storage URL that rejects requests carrying our
/// Authorization header, so it must be dropped on redirect.
private final class RedirectAuthStripper: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        var redirected = request
        redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        completionHandler(redirected)
    }
}

struct LiveUpdateHTTP: UpdateHTTP {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request, delegate: RedirectAuthStripper())
        guard let http = response as? HTTPURLResponse else { throw UpdateError.badResponse }
        return (data, http)
    }

    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        let (url, response) = try await URLSession.shared.download(for: request, delegate: RedirectAuthStripper())
        guard let http = response as? HTTPURLResponse else { throw UpdateError.badResponse }
        return (url, http)
    }
}

/// Used only by UI tests (UITEST_UPDATE_MODE = available | current | error) so the whole flow can be
/// exercised without a network or a real token.
struct MockUpdateHTTP: UpdateHTTP {
    let mode: String
    static let payload = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0, count: 100)

    private func response(for request: URLRequest, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url ?? URL(string: "https://example.invalid")!,
                        statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if mode == "error" { return (Data(), response(for: request, status: 401)) }
        let build = mode == "available" ? 999 : 1
        let json = """
        [{"id": 1, "tag_name": "v9.9.9-build.\(build)", "name": "StudyTrack 9.9.9 (build \(build))",
          "body": "Mock release notes: faster everything.", "draft": false, "prerelease": true,
          "published_at": "2026-10-17T10:28:59Z", "html_url": "https://example.invalid/release",
          "assets": [{"id": 1, "name": "StudyTrack.ipa", "size": \(Self.payload.count),
                      "url": "https://example.invalid/asset/1", "state": "uploaded"}]}]
        """
        return (Data(json.utf8), response(for: request))
    }

    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mock-\(UUID().uuidString).ipa")
        try Self.payload.write(to: tmp)
        return (tmp, response(for: request))
    }
}

// MARK: - Service

/// Checks GitHub Releases for a newer build and downloads the IPA.
///
/// iOS doesn't allow an app to install a new copy of itself, so the last step is handing the downloaded
/// IPA to AltStore / Sideloadly / SideStore through the share sheet. The repository is private, so a
/// read-only GitHub token (kept in the Keychain) is needed.
@MainActor
@Observable
final class UpdateService {
    enum Status: Equatable {
        case idle, needsToken, checking, upToDate, available(ReleaseInfo), failed(String)
    }

    enum DownloadState: Equatable {
        case idle, downloading, ready(URL), failed(String)
    }

    static let tokenKey = "github-token"
    private static let lastCheckedKey = "update.lastChecked"
    private static let checkInterval: TimeInterval = 6 * 3600

    private(set) var status: Status = .idle
    private(set) var download: DownloadState = .idle
    private(set) var lastChecked: Date?
    private(set) var hasToken = false

    let currentBuild: Int
    let currentVersion: String

    private let http: UpdateHTTP
    private let tokenProvider: () -> String?
    private let updatesDirectory: URL
    private let repo: String
    private let isMocked: Bool

    init(http: UpdateHTTP? = nil,
         tokenProvider: (() -> String?)? = nil,
         currentBuild: Int? = nil,
         currentVersion: String? = nil,
         updatesDirectory: URL? = nil,
         repo: String = "omni-gh549/study-track") {
        let mockMode = ProcessInfo.processInfo.environment["UITEST_UPDATE_MODE"]
        if let mockMode {
            self.http = MockUpdateHTTP(mode: mockMode)
            self.tokenProvider = { "mock-token" }
            self.isMocked = true
        } else {
            self.http = http ?? LiveUpdateHTTP()
            self.tokenProvider = tokenProvider ?? { SecretStore.get(UpdateService.tokenKey) }
            self.isMocked = false
        }
        let info = Bundle.main.infoDictionary
        self.currentBuild = currentBuild ?? Int(info?["CFBundleVersion"] as? String ?? "") ?? 0
        self.currentVersion = currentVersion ?? (info?["CFBundleShortVersionString"] as? String ?? "0")
        self.repo = repo
        let docs = (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        self.updatesDirectory = updatesDirectory ?? docs.appendingPathComponent("Updates", isDirectory: true)

        hasToken = self.tokenProvider() != nil
        if !isMocked {
            let stamp = UserDefaults.standard.double(forKey: Self.lastCheckedKey)
            lastChecked = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        }
        pruneDownloads(keeping: nil)
    }

    // MARK: Token

    func saveToken(_ raw: String) {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        SecretStore.set(token, for: Self.tokenKey)
        hasToken = tokenProvider() != nil
        status = .idle
    }

    func removeToken() {
        SecretStore.remove(Self.tokenKey)
        hasToken = tokenProvider() != nil
        status = .needsToken
        download = .idle
    }

    // MARK: Checking

    func autoCheckIfDue() async {
        guard hasToken else { return }
        if let lastChecked, Date.now.timeIntervalSince(lastChecked) < Self.checkInterval, !isMocked { return }
        if case .checking = status { return }
        await check()
    }

    func check() async {
        guard let token = tokenProvider() else {
            status = .needsToken
            return
        }
        status = .checking
        do {
            guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=15") else {
                throw UpdateError.badResponse
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            Self.applyHeaders(&request, token: token, accept: "application/vnd.github+json")
            let (data, response) = try await http.data(for: request)
            try Self.validate(response)
            let releases = try UpdateLogic.releases(fromJSON: data)

            lastChecked = .now
            if !isMocked { UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.lastCheckedKey) }
            if let latest = UpdateLogic.latest(in: releases), UpdateLogic.isNewer(latest, than: currentBuild) {
                status = .available(latest)
            } else {
                status = .upToDate
                download = .idle
            }
        } catch {
            status = .failed(Self.message(for: error))
        }
    }

    // MARK: Downloading

    /// Saves a safety backup first, then downloads and verifies the IPA.
    func startDownload(_ release: ReleaseInfo, context: ModelContext?) async {
        guard let token = tokenProvider() else {
            status = .needsToken
            return
        }
        if case .downloading = download { return }
        download = .downloading
        if let context { AutoBackup.write(prefix: "pre-update", context: context) }

        do {
            var request = URLRequest(url: release.assetURL)
            request.timeoutInterval = 120
            Self.applyHeaders(&request, token: token, accept: "application/octet-stream")
            let (temp, response) = try await http.download(for: request)
            try Self.validate(response)

            let fm = FileManager.default
            try fm.createDirectory(at: updatesDirectory, withIntermediateDirectories: true)
            let destination = updatesDirectory
                .appendingPathComponent("StudyTrack-\(release.version)-build\(release.build).ipa")
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: temp, to: destination)

            guard Self.looksLikeValidIPA(destination, expectedSize: release.assetSize) else {
                try? fm.removeItem(at: destination)
                throw UpdateError.corruptDownload
            }
            pruneDownloads(keeping: destination)
            download = .ready(destination)
        } catch {
            download = .failed(Self.message(for: error))
        }
    }

    func resetDownload() { download = .idle }

    // MARK: Helpers

    static func applyHeaders(_ request: inout URLRequest, token: String, accept: String) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    }

    static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401: throw UpdateError.unauthorized
        case 403:
            throw response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0"
                ? UpdateError.rateLimited : UpdateError.unauthorized
        case 404: throw UpdateError.notFound
        case 429: throw UpdateError.rateLimited
        default: throw UpdateError.server(response.statusCode)
        }
    }

    static func message(for error: Error) -> String {
        if let update = error as? UpdateError { return update.localizedDescription }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost:
                return "Couldn't reach GitHub. Check your internet connection."
            default: return url.localizedDescription
            }
        }
        if error is DecodingError { return UpdateError.badResponse.localizedDescription }
        return error.localizedDescription
    }

    /// The right size, and starts with the zip signature "PK\u{3}\u{4}" (an .ipa is a zip).
    static func looksLikeValidIPA(_ url: URL, expectedSize: Int) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        if expectedSize > 0 && size != expectedSize { return false }
        guard size >= 4, let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let magic = (try? handle.read(upToCount: 4)) ?? Data()
        return magic == Data([0x50, 0x4B, 0x03, 0x04])
    }

    /// Removes downloaded installers that are older than (or the same as) what's installed now.
    private func pruneDownloads(keeping keep: URL?) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: updatesDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension.lowercased() == "ipa" && file != keep {
            let name = file.deletingPathExtension().lastPathComponent
            let build = name.components(separatedBy: "-build").last.flatMap { Int($0) } ?? 0
            if keep != nil || build <= currentBuild { try? fm.removeItem(at: file) }
        }
    }
}
