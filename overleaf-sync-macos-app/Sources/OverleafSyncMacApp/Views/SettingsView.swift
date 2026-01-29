import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Form {
      Section(model.ui("Language", "语言")) {
        Picker(model.ui("Language", "语言"), selection: $model.language) {
          ForEach(AppLanguage.allCases) { lang in
            Text(lang.label).tag(lang)
          }
        }
        .pickerStyle(.segmented)
      }

      Section(model.ui("Overleaf", "Overleaf")) {
        TextField(model.ui("Base URL", "Base URL"), text: $model.baseURL)
      }

      Section(model.ui("Workspace", "工作区")) {
        HStack {
          Text(model.workspaceRoot?.path ?? model.ui("Not set", "未设置"))
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          Button(model.ui("Choose…", "选择…")) { model.pickWorkspaceRoot() }
        }
      }

      Section(model.ui("Login (optional)", "登录（可选）")) {
        TextField(model.ui("Email", "邮箱"), text: $model.email)
        SecureField(model.ui("Password (not saved)", "密码（不保存）"), text: $model.password)
        Button(model.ui("Login", "登录")) { Task { await model.login() } }
      }

      Section(model.ui("Remote changes", "远端变更")) {
        Toggle(model.ui("Auto-fetch remote changes", "自动拉取远端变更"), isOn: $model.autoRemoteFetchEnabled)
        Stepper(
          value: $model.autoRemoteFetchIntervalMinutes,
          in: 5...240,
          step: 5
        ) {
          Text(
            model.ui(
              "Interval: \(model.autoRemoteFetchIntervalMinutes) min",
              "间隔：\(model.autoRemoteFetchIntervalMinutes) 分钟"
            )
          )
        }
        .disabled(!model.autoRemoteFetchEnabled)
        Text(
          model.ui(
            "Auto-fetch creates a remote inbox batch only when changes exist. A badge will appear on the project.",
            "仅在检测到网页端改动时，Auto-fetch 才会创建一个远端收件箱批次；项目列表会显示徽标。"
          )
        )
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section(model.ui("Local folders", "本地文件夹")) {
        HStack {
          Text(model.ui("Local folder", "本地文件夹"))
          Spacer()
          Text(model.localFolder?.path ?? model.ui("Not set", "未设置"))
            .lineLimit(1)
            .truncationMode(.middle)
          Button(model.ui("Choose…", "选择…")) { model.pickLocalFolder() }
        }
        HStack {
          Text(model.ui("Pull parent", "下载到"))
          Spacer()
          Text(model.pullParentFolder?.path ?? model.ui("Not set", "未设置"))
            .lineLimit(1)
            .truncationMode(.middle)
          Button(model.ui("Choose…", "选择…")) { model.pickPullParentFolder() }
        }
      }

      Section(model.ui("Storage", "存储")) {
        HStack {
          Text(model.ui("Inbox batches", "收件箱批次"))
          Spacer()
          Text("\(model.storageStatus.inboxBatchCount)")
            .foregroundStyle(.secondary)
        }
        HStack {
          Text(
            model.ui(
              "Inbox over limit (keep \(AppConstants.inboxKeepLastPerProject)/project)",
              "收件箱超限（每项目保留 \(AppConstants.inboxKeepLastPerProject) 个）"
            )
          )
          Spacer()
          Text("\(model.storageStatus.inboxOverLimitBatches)")
            .foregroundStyle(model.storageStatus.inboxOverLimitBatches > 0 ? .orange : .secondary)
        }

        HStack(spacing: 12) {
          Button(model.ui("Refresh", "刷新")) { Task { await model.refreshStorageStatus() } }
          Button(model.ui("Clean inbox…", "清理收件箱…")) { Task { await model.prepareInboxCleanup() } }
            .disabled(model.storageStatus.inboxOverLimitBatches == 0)
          Spacer()
          Button(model.ui("Open inbox", "打开收件箱")) { model.openInboxFolder() }
          Button(model.ui("Open backups", "打开备份")) { model.openBackupsFolder() }
        }

        Text(
          model.ui(
            "Inbox holds remote snapshots fetched for applying web edits. Cleaning removes old batches only (manual snapshots are separate).",
            "收件箱用于存放“网页端改动”的远端快照；清理只会删除旧的批次（手动快照是独立的）。"
          )
        )
          .font(.caption)
          .foregroundStyle(.secondary)

        Divider()

        HStack {
          Text(model.ui("Local snapshots (pinned/auto)", "本地快照（置顶/自动）"))
          Spacer()
          Text("\(model.storageStatus.snapshotPinnedCount)/\(model.storageStatus.snapshotAutoCount)")
            .foregroundStyle(.secondary)
        }
        HStack {
          Text(
            model.ui(
              "Auto over limit (keep \(AppConstants.autoSnapshotKeepLastPerProject)/project)",
              "自动快照超限（每项目保留 \(AppConstants.autoSnapshotKeepLastPerProject) 个）"
            )
          )
          Spacer()
          Text("\(model.storageStatus.snapshotAutoOverLimitCount)")
            .foregroundStyle(model.storageStatus.snapshotAutoOverLimitCount > 0 ? .orange : .secondary)
        }

        HStack(spacing: 12) {
          Button(model.ui("Clean local snapshots…", "清理本地快照…")) { Task { await model.prepareLocalSnapshotsCleanup() } }
            .disabled(model.storageStatus.snapshotAutoOverLimitCount == 0)
          Spacer()
          Button(model.ui("Open snapshots", "打开快照")) { model.openSnapshotsRootFolder() }
        }

        Text(
          model.ui(
            "Pinned snapshots are kept forever. Cleaning removes only old auto snapshots (never deletes pinned).",
            "置顶快照会永久保留；清理只会删除旧的自动快照（永不删除置顶）。"
          )
        )
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .frame(minWidth: 520)
    .confirmationDialog(
      model.ui("Clean inbox?", "清理收件箱？"),
      isPresented: Binding(
        get: { model.inboxCleanupPrompt != nil },
        set: { if !$0 { model.inboxCleanupPrompt = nil } }
      ),
      titleVisibility: .visible,
      presenting: model.inboxCleanupPrompt
    ) { prompt in
      Button(
        model.ui(
          "Delete \(prompt.candidateCount) batch folder(s)",
          "删除 \(prompt.candidateCount) 个批次文件夹"
        ),
        role: .destructive
      ) {
        Task { await model.confirmInboxCleanup(prompt) }
        model.inboxCleanupPrompt = nil
      }
      Button(model.ui("Cancel", "取消"), role: .cancel) { model.inboxCleanupPrompt = nil }
    } message: { prompt in
      Text(
        model.ui(
          """
          This will delete \(prompt.candidateCount) inbox batch folder(s) and keep only the latest \(prompt.keepLast) per project.

          Tip: you can pin a batch by creating a .keep file inside it.
          """,
          """
          这会删除 \(prompt.candidateCount) 个收件箱批次文件夹，并且每个项目只保留最近 \(prompt.keepLast) 个。

          小技巧：在批次文件夹里创建一个 .keep 文件即可“置顶”保留。
          """
        )
      )
    }
    .confirmationDialog(
      model.ui("Clean local snapshots?", "清理本地快照？"),
      isPresented: Binding(
        get: { model.localSnapshotsCleanupPrompt != nil },
        set: { if !$0 { model.localSnapshotsCleanupPrompt = nil } }
      ),
      titleVisibility: .visible,
      presenting: model.localSnapshotsCleanupPrompt
    ) { prompt in
      Button(
        model.ui(
          "Delete \(prompt.candidateCount) auto snapshot(s)",
          "删除 \(prompt.candidateCount) 个自动快照"
        ),
        role: .destructive
      ) {
        Task { await model.confirmLocalSnapshotsCleanup(prompt) }
        model.localSnapshotsCleanupPrompt = nil
      }
      Button(model.ui("Cancel", "取消"), role: .cancel) { model.localSnapshotsCleanupPrompt = nil }
    } message: { prompt in
      Text(
        model.ui(
          """
          This will delete \(prompt.candidateCount) auto snapshot folder(s) and keep only the latest \(prompt.keepLastAuto) auto snapshots per project.

          Pinned snapshots (with a .keep marker) are never deleted.
          """,
          """
          这会删除 \(prompt.candidateCount) 个自动快照文件夹，并且每个项目只保留最近 \(prompt.keepLastAuto) 个自动快照。

          置顶快照（带 .keep 标记）永远不会被删除。
          """
        )
      )
    }
  }
}
