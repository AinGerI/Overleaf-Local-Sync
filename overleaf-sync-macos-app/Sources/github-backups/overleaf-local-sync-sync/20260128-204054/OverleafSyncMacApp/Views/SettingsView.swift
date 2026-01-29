import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Form {
      Section("Overleaf") {
        TextField("Base URL", text: $model.baseURL)
      }

      Section("Workspace") {
        HStack {
          Text(model.workspaceRoot?.path ?? "Not set")
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          Button("Choose…") { model.pickWorkspaceRoot() }
        }
      }

      Section("Login (optional)") {
        TextField("Email", text: $model.email)
        SecureField("Password (not saved)", text: $model.password)
        Button("Login") { Task { await model.login() } }
      }

      Section("Remote changes") {
        Toggle("Auto-fetch remote changes", isOn: $model.autoRemoteFetchEnabled)
        Stepper(
          value: $model.autoRemoteFetchIntervalMinutes,
          in: 5...240,
          step: 5
        ) {
          Text("Interval: \(model.autoRemoteFetchIntervalMinutes) min")
        }
        .disabled(!model.autoRemoteFetchEnabled)
        Text("Auto-fetch creates a remote inbox batch only when changes exist. A badge will appear on the project.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Local folders") {
        HStack {
          Text("Local folder")
          Spacer()
          Text(model.localFolder?.path ?? "Not set")
            .lineLimit(1)
            .truncationMode(.middle)
          Button("Choose…") { model.pickLocalFolder() }
        }
        HStack {
          Text("Pull parent")
          Spacer()
          Text(model.pullParentFolder?.path ?? "Not set")
            .lineLimit(1)
            .truncationMode(.middle)
          Button("Choose…") { model.pickPullParentFolder() }
        }
      }

      Section("Storage") {
        HStack {
          Text("Inbox batches")
          Spacer()
          Text("\(model.storageStatus.inboxBatchCount)")
            .foregroundStyle(.secondary)
        }
        HStack {
          Text("Inbox over limit (keep \(AppConstants.inboxKeepLastPerProject)/project)")
          Spacer()
          Text("\(model.storageStatus.inboxOverLimitBatches)")
            .foregroundStyle(model.storageStatus.inboxOverLimitBatches > 0 ? .orange : .secondary)
        }

        HStack(spacing: 12) {
          Button("Refresh") { Task { await model.refreshStorageStatus() } }
          Button("Clean inbox…") { Task { await model.prepareInboxCleanup() } }
            .disabled(model.storageStatus.inboxOverLimitBatches == 0)
          Spacer()
          Button("Open inbox") { model.openInboxFolder() }
          Button("Open backups") { model.openBackupsFolder() }
        }

        Text("Inbox holds remote snapshots fetched for applying web edits. Cleaning removes old batches only (manual snapshots are separate).")
          .font(.caption)
          .foregroundStyle(.secondary)

        Divider()

        HStack {
          Text("Local snapshots (pinned/auto)")
          Spacer()
          Text("\(model.storageStatus.snapshotPinnedCount)/\(model.storageStatus.snapshotAutoCount)")
            .foregroundStyle(.secondary)
        }
        HStack {
          Text("Auto over limit (keep \(AppConstants.autoSnapshotKeepLastPerProject)/project)")
          Spacer()
          Text("\(model.storageStatus.snapshotAutoOverLimitCount)")
            .foregroundStyle(model.storageStatus.snapshotAutoOverLimitCount > 0 ? .orange : .secondary)
        }

        HStack(spacing: 12) {
          Button("Clean local snapshots…") { Task { await model.prepareLocalSnapshotsCleanup() } }
            .disabled(model.storageStatus.snapshotAutoOverLimitCount == 0)
          Spacer()
          Button("Open snapshots") { model.openSnapshotsRootFolder() }
        }

        Text("Pinned snapshots are kept forever. Cleaning removes only old auto snapshots (never deletes pinned).")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .frame(minWidth: 520)
    .confirmationDialog(
      "Clean inbox?",
      isPresented: Binding(
        get: { model.inboxCleanupPrompt != nil },
        set: { if !$0 { model.inboxCleanupPrompt = nil } }
      ),
      titleVisibility: .visible,
      presenting: model.inboxCleanupPrompt
    ) { prompt in
      Button("Delete \(prompt.candidateCount) batch folder(s)", role: .destructive) {
        Task { await model.confirmInboxCleanup(prompt) }
        model.inboxCleanupPrompt = nil
      }
      Button("Cancel", role: .cancel) { model.inboxCleanupPrompt = nil }
    } message: { prompt in
      Text(
        """
        This will delete \(prompt.candidateCount) inbox batch folder(s) and keep only the latest \(prompt.keepLast) per project.

        Tip: you can pin a batch by creating a .keep file inside it.
        """
      )
    }
    .confirmationDialog(
      "Clean local snapshots?",
      isPresented: Binding(
        get: { model.localSnapshotsCleanupPrompt != nil },
        set: { if !$0 { model.localSnapshotsCleanupPrompt = nil } }
      ),
      titleVisibility: .visible,
      presenting: model.localSnapshotsCleanupPrompt
    ) { prompt in
      Button("Delete \(prompt.candidateCount) auto snapshot(s)", role: .destructive) {
        Task { await model.confirmLocalSnapshotsCleanup(prompt) }
        model.localSnapshotsCleanupPrompt = nil
      }
      Button("Cancel", role: .cancel) { model.localSnapshotsCleanupPrompt = nil }
    } message: { prompt in
      Text(
        """
        This will delete \(prompt.candidateCount) auto snapshot folder(s) and keep only the latest \(prompt.keepLastAuto) auto snapshots per project.

        Pinned snapshots (with a .keep marker) are never deleted.
        """
      )
    }
  }
}
