import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Lets the downloaded installer be saved anywhere via the system file picker (e.g. Files › Downloads).
struct IPADocument: FileDocument {
    static var ipaType: UTType { UTType(filenameExtension: "ipa") ?? .data }
    static var readableContentTypes: [UTType] { [ipaType] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// The "App updates" section of Settings.
struct UpdatesSection: View {
    @Environment(UpdateService.self) private var updates
    @Environment(\.modelContext) private var context
    @State private var tokenInput = ""
    @State private var exportDocument: IPADocument?
    @State private var showingExporter = false
    @State private var exportMessage: String?

    var body: some View {
        Section {
            LabeledContent("Installed", value: "\(updates.currentVersion) (build \(updates.currentBuild))")
            statusRows

            Button {
                Task { await updates.check() }
            } label: {
                Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isChecking || !updates.hasToken)

            tokenRows
        } header: {
            Text("App updates")
        } footer: {
            Text("iOS doesn't let an app replace itself. When an update is available, download it here and open it in AltStore, SideStore or Sideloadly — installing over the top keeps your data. A backup is saved first.")
        }
    }

    private var isChecking: Bool {
        if case .checking = updates.status { return true }
        return false
    }

    @ViewBuilder
    private var statusRows: some View {
        switch updates.status {
        case .idle:
            if updates.hasToken {
                Text("Not checked yet.").foregroundStyle(.secondary)
            } else {
                Text("Add a GitHub token below to check for updates.").foregroundStyle(.secondary)
            }
        case .needsToken:
            Text("Add a GitHub token below to check for updates.").foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 10) {
                ProgressView()
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("You're up to date", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if let last = updates.lastChecked {
                Text("Last checked \(last.formatted(.relative(presentation: .named)))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .available(let release):
            availableRows(release)
        }
    }

    @ViewBuilder
    private func availableRows(_ release: ReleaseInfo) -> some View {
        Label("Update available", systemImage: "arrow.down.circle.fill")
            .foregroundStyle(Color.accentColor)
            .accessibilityIdentifier("update.available")
        LabeledContent("New version", value: "\(release.version) (build \(release.build))")
        if !release.notes.isEmpty {
            Text(release.notes)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(6)
        }
        switch updates.download {
        case .idle:
            Button {
                Task { await updates.startDownload(release, context: context) }
            } label: {
                Label("Download update", systemImage: "icloud.and.arrow.down")
            }
        case .downloading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Downloading…").foregroundStyle(.secondary)
            }
        case .ready(let file):
            ShareLink(item: file) {
                Label("Install update…", systemImage: "square.and.arrow.up")
            }
            Button {
                exportDocument = IPADocument(data: (try? Data(contentsOf: file)) ?? Data())
                exportMessage = nil
                showingExporter = true
            } label: {
                Label("Save to Files…", systemImage: "folder")
            }
            .fileExporter(isPresented: $showingExporter, document: exportDocument,
                          contentType: IPADocument.ipaType,
                          defaultFilename: file.deletingPathExtension().lastPathComponent) { result in
                switch result {
                case .success: exportMessage = "Saved. Open it from the Files app (the folder you picked)."
                case .failure(let error): exportMessage = "Couldn't save: \(error.localizedDescription)"
                }
            }
            if let exportMessage {
                Text(exportMessage).font(.footnote).foregroundStyle(.secondary)
            }
            Text("File: \(file.lastPathComponent)")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Install: choose AltStore / SideStore / Sideloadly from the share sheet. Using LiveContainer? Tap “Save to Files…” (pick Downloads), then in LiveContainer tap + and choose that file.")
                .font(.footnote).foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Button("Try download again") {
                updates.resetDownload()
                Task { await updates.startDownload(release, context: context) }
            }
        }
    }

    @ViewBuilder
    private var tokenRows: some View {
        DisclosureGroup("GitHub access") {
            if updates.hasToken {
                Label("Token saved on this device", systemImage: "key.fill").foregroundStyle(.secondary)
                Button("Remove token", role: .destructive) { updates.removeToken() }
            } else {
                SecureField("Paste GitHub token", text: $tokenInput)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Save token") {
                    updates.saveToken(tokenInput)
                    tokenInput = ""
                    Task { await updates.check() }
                }
                .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                Text("The repository is private, so the app needs a read-only token: GitHub › Settings › Developer settings › Fine-grained tokens › Generate. Choose “Only select repositories” → this repo, and set Contents to Read-only. The token is stored in the Keychain and never leaves your phone except to talk to GitHub.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
