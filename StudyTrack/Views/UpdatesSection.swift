import SwiftData
import SwiftUI

struct ExportItem: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Saves a copy of the downloaded installer anywhere via the system file picker (e.g. Files › Downloads).
/// It copies the real file, so the name (ending in .ipa) and every byte stay exactly as downloaded.
struct IPAExporter: UIViewControllerRepresentable {
    let file: URL
    var onFinish: (_ saved: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish(true) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish(false) }
    }
}

/// The "App updates" section of Settings.
struct UpdatesSection: View {
    @Environment(UpdateService.self) private var updates
    @Environment(\.modelContext) private var context
    @State private var tokenInput = ""
    @State private var exportItem: ExportItem?
    @State private var exportMessage: String?

    var body: some View {
        Section {
            LabeledContent("Installed", value: "\(updates.currentVersion) (build \(updates.currentBuild))")
            LabeledContent("Edition", value: updates.editionName)
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
                exportMessage = nil
                exportItem = ExportItem(url: file)
            } label: {
                Label("Save to Files…", systemImage: "folder")
            }
            .sheet(item: $exportItem) { item in
                IPAExporter(file: item.url) { saved in
                    exportItem = nil
                    if saved { exportMessage = "Saved. Open it from the Files app (the folder you picked)." }
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
