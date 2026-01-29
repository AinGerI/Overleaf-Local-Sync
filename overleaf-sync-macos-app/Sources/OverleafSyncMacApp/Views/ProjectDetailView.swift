import AppKit
import SwiftUI

private enum ProjectDetailTab: String, CaseIterable, Hashable {
  case sync = "Sync"
  case remote = "Remote"
  case snapshots = "Snapshots"
  case logs = "Logs"

  var titleEn: String { rawValue }

  var titleZh: String {
    switch self {
    case .sync: "同步"
    case .remote: "远端"
    case .snapshots: "快照"
    case .logs: "日志"
    }
  }
}

struct ProjectDetailView: View {
  @EnvironmentObject private var model: AppModel
  @State private var showDryRunConfirmation: Bool = false
  @State private var copiedToastToken: UUID? = nil
  @State private var detailTab: ProjectDetailTab = .sync

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let project = model.selectedProject {
        let cfgProjectId = model.localFolderConfig?.projectId
        let isProjectsRootSelected = model.projectsRoot != nil && model.localFolder == model.projectsRoot
        let isLinkedToSelected = !isProjectsRootSelected && (cfgProjectId == project.id)

        VStack(alignment: .leading, spacing: 6) {
          Text(project.name).font(.title2).bold()
          HStack(spacing: 10) {
            Text(project.id)
              .font(.system(.footnote, design: .monospaced))
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
              .lineLimit(nil)
              .fixedSize(horizontal: false, vertical: true)
              .layoutPriority(1)
            Button {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(project.id, forType: .string)

              let token = UUID()
              copiedToastToken = token
              Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                if copiedToastToken == token {
                  copiedToastToken = nil
                }
              }
            } label: {
              Text(model.ui("Copy ID", "复制 ID"))
            }
            .buttonStyle(PressableLinkButtonStyle())

            if copiedToastToken != nil {
              Label(model.ui("Copied", "已复制"), systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
          }
          .animation(.easeInOut(duration: 0.15), value: copiedToastToken != nil)
        }

        Divider()

        Picker("", selection: $detailTab) {
          ForEach(ProjectDetailTab.allCases, id: \.self) { tab in
            Text(model.ui(tab.titleEn, tab.titleZh)).tag(tab)
          }
        }
        .pickerStyle(.segmented)

        if detailTab == .logs {
          LogView()
            .frame(minHeight: 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 12) {
	              switch detailTab {
	              case .sync:
	                GroupBox {
	                  VStack(alignment: .leading, spacing: 8) {
	                    HStack {
	                      Text(model.localFolder?.path ?? model.ui("Not set", "未设置"))
	                        .lineLimit(1)
	                        .truncationMode(.middle)
	                      Spacer()
	                      Button(model.ui("Choose…", "选择…")) { model.pickLocalFolder() }
	                    }

	                    if isProjectsRootSelected {
	                      VStack(alignment: .leading, spacing: 6) {
	                        Text(model.ui("You selected the overleaf-projects root folder.", "你选中了 overleaf-projects 的根目录。"))
	                          .foregroundStyle(.red)
	                        Text(
	                          model.ui(
	                            "Choose a specific project folder under overleaf-projects, e.g. overleaf-projects/报告撰写.",
	                            "请选择 overleaf-projects 下的具体项目文件夹，例如 overleaf-projects/报告撰写。"
	                          )
	                        )
	                          .font(.caption)
	                          .foregroundStyle(.secondary)
	                        Button(model.ui("Create a new local project…", "创建新的本地项目…")) {
	                          if let root = model.projectsRoot {
	                            model.newFolderPrompt = NewFolderPrompt(parent: root)
	                          }
	                        }
	                        if let pid = cfgProjectId, !pid.isEmpty {
	                          Text(
	                            model.ui(
	                              "This root folder currently contains .ol-sync.json linked to \(pid.prefix(8))…, which can cause confusing sync behavior.",
	                              "该根目录目前包含一个 .ol-sync.json（链接到 \(pid.prefix(8))…），可能导致同步行为混乱。"
	                            )
	                          )
	                            .font(.caption)
	                            .foregroundStyle(.secondary)
	                          Button(model.ui("Fix: move root .ol-sync.json aside…", "修复：把根目录的 .ol-sync.json 挪开…")) {
	                            model.prepareMoveRootConfigAside()
	                          }
	                        }
	                      }
	                    }

                    if let cfgProjectId {
                      let linkedName = model.projects.first(where: { $0.id == cfgProjectId })?.name
                      let linkedLabel = linkedName ?? "\(cfgProjectId.prefix(8))…"

	                      VStack(alignment: .leading, spacing: 4) {
	                        HStack(spacing: 8) {
	                          Text(model.ui("This folder is linked to:", "此文件夹已连接到："))
	                            .font(.caption)
	                            .foregroundStyle(.secondary)
	                          Text(linkedLabel)
	                            .font(.caption)
                            .foregroundStyle(isLinkedToSelected ? .green : .orange)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        }

	                        if !isLinkedToSelected {
	                          Text(
	                            model.ui(
	                              "Selected project is different. Choose the correct folder for this project, or click Link to re-bind.",
	                              "当前选中的项目不同。请选择该项目对应的文件夹，或点击“连接”重新绑定。"
	                            )
	                          )
	                            .font(.caption)
	                            .foregroundStyle(.secondary)
	                        }
	                      }
	                    } else {
	                      Text(model.ui("Not linked yet (no .ol-sync.json).", "尚未连接（缺少 .ol-sync.json）。"))
	                        .font(.caption)
	                        .foregroundStyle(.secondary)
	                    }
	                  }
	                } label: {
	                  Text(model.ui("Local folder", "本地文件夹"))
	                }

	                GroupBox {
	                  if let dir = model.linkedFoldersByProjectId[project.id] {
	                    HStack {
	                      Text(dir.path)
	                        .lineLimit(1)
	                        .truncationMode(.middle)
	                      Spacer()
	                      Button(model.ui("Use", "使用")) { model.localFolder = dir }
	                      Button(model.ui("Start watch", "启动监听")) {
	                        model.localFolder = dir
	                        model.startWatchForLocalFolder()
	                      }
	                    }
	                  } else {
	                    VStack(alignment: .leading, spacing: 6) {
	                      Text(model.ui("No linked local folder found under overleaf-projects.", "在 overleaf-projects 下未找到已连接的本地文件夹。"))
	                        .foregroundStyle(.secondary)
	                      Text(
	                        model.ui(
	                          "Tip: pull this project, or choose a folder and click Link once.",
	                          "提示：你可以先拉取该项目，或选择一个文件夹并点击一次“连接”。"
	                        )
	                      )
	                        .font(.caption)
	                        .foregroundStyle(.secondary)
	                    }
	                  }
	                } label: {
	                  Text(model.ui("Selected project link", "已连接的本地文件夹"))
	                }

	                HStack(spacing: 12) {
	                  Button(model.ui("Link", "连接")) { Task { await model.linkSelectedProject() } }
	                    .disabled(model.localFolder == nil || isProjectsRootSelected)
	                  Button(model.ui("Pull (download)", "拉取（下载）")) { Task { await model.pullSelectedProject() } }
	                  Button(model.ui("Create (from folder)", "创建（从文件夹）")) { Task { await model.createRemoteProjectFromLocalFolder() } }
	                    .disabled(model.localFolder == nil)
	                }

	                GroupBox {
	                  HStack {
	                    Stepper(
	                      value: $model.pushConcurrency,
	                      in: 1...16,
	                      step: 1,
	                      label: { Text(model.ui("Concurrency: \(model.pushConcurrency)", "并发：\(model.pushConcurrency)")) }
	                    )
	                    Spacer()
	                    Button(model.ui("Dry-run", "预演")) { showDryRunConfirmation = true }
	                      .disabled(!isLinkedToSelected)
	                    Button(model.ui("Push", "推送")) { Task { await model.pushLocalFolder(dryRun: false) } }
	                      .disabled(!isLinkedToSelected)
	                  }
	                } label: {
	                  Text(model.ui("Push", "推送"))
	                }

	                GroupBox {
	                  HStack {
	                    Button(model.ui("Start watch", "启动监听")) { model.startWatchForLocalFolder() }
	                      .disabled(!isLinkedToSelected)
	                    Spacer()
	                    if let dir = model.localFolder {
	                      let internalRunning = model.watches.contains(where: { $0.dir == dir && $0.isRunning })
	                      let externalRunning = model.externalWatches.contains(where: { $0.dir.standardizedFileURL == dir.standardizedFileURL })
	                      if internalRunning || externalRunning {
	                        Text(model.ui("Running", "运行中"))
	                          .foregroundStyle(.green)
	                      }
	                    }
	                  }
	                } label: {
	                  Text(model.ui("Watch", "监听"))
	                }

	                GroupBox {
	                  VStack(alignment: .leading, spacing: 10) {
	                    HStack(spacing: 10) {
	                      if project.archived {
	                        Label(model.ui("Archived", "已归档"), systemImage: "archivebox.fill")
	                          .foregroundStyle(.orange)
	                      }
	                      if project.trashed {
	                        Label(model.ui("Trashed", "在废纸篓"), systemImage: "trash.fill")
	                          .foregroundStyle(.red)
	                      }
	                      if !project.archived && !project.trashed {
	                        Text(model.ui("Active", "正常"))
	                          .foregroundStyle(.secondary)
	                      }
	                      Spacer()
	                    }

	                    HStack(spacing: 12) {
	                      if project.archived {
	                        Button(model.ui("Unarchive", "取消归档")) { Task { await model.unarchiveSelectedProject() } }
	                      } else {
	                        Button(model.ui("Archive", "归档")) { Task { await model.archiveSelectedProject() } }
	                      }

	                      if project.trashed {
	                        Button(model.ui("Restore from Trash", "从废纸篓恢复")) { Task { await model.untrashSelectedProject() } }
	                      }

	                      Spacer()

	                      Button(model.ui("Delete / Trash…", "删除/移到废纸篓…")) { model.prepareDeleteSelectedProject() }
	                        .tint(.red)
	                    }

	                    Text(
	                      model.ui(
	                        "Deletion supports cloud + local options and requires typing the project name. Autowatch logs are kept.",
	                        "删除支持云端 + 本地选项，并要求输入项目名称确认。自动监听日志会保留。"
	                      )
	                    )
	                      .font(.caption)
	                      .foregroundStyle(.secondary)
	                      .fixedSize(horizontal: false, vertical: true)
	                  }
	                } label: {
	                  Text(model.ui("Project actions", "项目操作"))
	                }

	              case .remote:
	                let canOperateOnProjectFolder = model.linkedFoldersByProjectId[project.id] != nil || isLinkedToSelected
	                let pending = model.selectedProjectInboxBatches.filter { $0.state == .pending }
	                let pendingCount = pending.count
	                let pendingChanges = pending.reduce(0) { $0 + $1.changeCount }
	                GroupBox {
	                  VStack(alignment: .leading, spacing: 8) {
	                    HStack(spacing: 10) {
	                      if pendingChanges > 0 {
	                        RemoteCountBadge(count: pendingChanges)
	                        Text(
	                          model.ui(
	                            pendingCount == 1
	                              ? "pending change(s) (1 batch)"
	                              : "pending change(s) (\(pendingCount) batches)",
	                            "待应用：\(pendingChanges) 处（\(pendingCount) 批次）"
	                          )
	                        )
	                          .foregroundStyle(.secondary)
	                      } else {
	                        Text(model.ui("No pending remote batches.", "没有待应用的远端批次。"))
	                          .foregroundStyle(.secondary)
	                      }
	                      Spacer()
	                      Button(model.ui("Fetch now", "立即拉取")) { Task { await model.fetchRemoteChangesForSelectedProject() } }
	                        .disabled(!canOperateOnProjectFolder)
	                      Button(model.ui("Apply latest…", "应用最新…")) { Task { await model.prepareApplyLatestRemoteChangesForSelectedProject() } }
	                        .disabled(!canOperateOnProjectFolder)
	                    }

	                    Text(
	                      model.ui(
	                        "Auto-fetch runs every \(model.autoRemoteFetchIntervalMinutes) min (Settings → Remote changes).",
	                        "自动拉取每 \(model.autoRemoteFetchIntervalMinutes) 分钟运行一次（设置 → 远端变更）。"
	                      )
	                    )
	                      .font(.caption)
	                      .foregroundStyle(.secondary)
	                  }
	                } label: {
	                  Text(model.ui("Remote changes", "远端变更"))
	                }

	                GroupBox {
	                  let batches = Array(model.selectedProjectInboxBatches.prefix(AppConstants.inboxKeepLastPerProject))
	                  if batches.isEmpty {
	                    Text(model.ui("No inbox batches yet.", "暂无收件箱批次。"))
	                      .font(.caption)
	                      .foregroundStyle(.secondary)
	                  } else {
	                    List {
	                      ForEach(batches) { batch in
                        HStack(spacing: 10) {
                          Image(systemName: batch.state == .pending ? "tray.and.arrow.down.fill" : "checkmark.circle.fill")
                            .foregroundStyle(batch.state == .pending ? .orange : .green)
	                          VStack(alignment: .leading, spacing: 2) {
	                            Text(batch.createdAtDisplay)
	                            Text(
	                              model.ui(
	                                "added=\(batch.addedCount), modified=\(batch.modifiedCount), deleted=\(batch.deletedCount)",
	                                "新增=\(batch.addedCount)，修改=\(batch.modifiedCount)，删除=\(batch.deletedCount)"
	                              )
	                            )
	                              .font(.caption)
	                              .foregroundStyle(.secondary)
	                              .lineLimit(1)
	                              .truncationMode(.tail)
	                          }
	                          Spacer()
	                          if batch.state == .pending {
	                            Button(model.ui("Apply…", "应用…")) { model.prepareApplyInboxBatch(batch) }
	                              .buttonStyle(.borderless)
	                              .disabled(!canOperateOnProjectFolder)
	                          } else {
	                            Text(model.ui("Applied", "已应用"))
	                              .font(.caption)
	                              .foregroundStyle(.secondary)
	                          }
	                          Button(model.ui("Open", "打开")) { model.openInboxBatchFolder(batch) }
	                            .buttonStyle(.borderless)
	                        }
	                      }
	                    }
	                    .frame(maxHeight: 260)
	                  }
	                } label: {
	                  Text(model.ui("Inbox (recent)", "收件箱（最近）"))
	                }

	              case .snapshots:
	                let canOperateOnProjectFolder = model.linkedFoldersByProjectId[project.id] != nil || isLinkedToSelected
	                GroupBox {
	                  VStack(alignment: .leading, spacing: 8) {
	                    Text(
	                      model.ui(
	                        "Snapshots are manual checkpoints. Auto snapshots can be cleaned up (keep last 5). Pinned snapshots are kept forever.",
	                        "快照是手动检查点。自动快照可清理（每项目保留最近 5 个）；置顶快照永久保留。"
	                      )
	                    )
	                      .font(.caption)
	                      .foregroundStyle(.secondary)
	                      .lineLimit(1)
	                      .truncationMode(.tail)
	                      .frame(maxWidth: .infinity, alignment: .leading)
	                      .help(
	                        model.ui(
	                          "Auto snapshots are eligible for cleanup (keep last 5 per project). Pinned snapshots are kept forever.",
	                          "自动快照可清理（每项目保留最近 5 个）；置顶快照永久保留。"
	                        )
	                      )

	                    HStack(spacing: 12) {
	                      Button(model.ui("Save snapshot", "保存快照")) { Task { await model.saveAutoSnapshotForSelectedProject() } }
	                        .disabled(!canOperateOnProjectFolder)
	                      Button(model.ui("Pin snapshot", "置顶快照")) { Task { await model.savePinnedSnapshotForSelectedProject() } }
	                        .disabled(!canOperateOnProjectFolder)
	                      Button(model.ui("Open snapshots", "打开快照")) { model.openSnapshotsFolderForSelectedProject() }
	                        .disabled(!canOperateOnProjectFolder)
	                      Spacer()
	                    }
	                  }
	                } label: {
	                  Text(model.ui("Snapshots", "快照"))
	                }

	                GroupBox {
	                  let pinned = model.selectedProjectSnapshots.filter { $0.isPinned }
	                  let auto = model.selectedProjectSnapshots.filter { !$0.isPinned }
	                  let recentAuto = Array(auto.prefix(AppConstants.autoSnapshotKeepLastPerProject))
	                  let display = pinned + recentAuto

	                  if display.isEmpty {
	                    Text(model.ui("No snapshots yet.", "暂无快照。"))
	                      .font(.caption)
	                      .foregroundStyle(.secondary)
	                  } else {
	                    List {
	                      ForEach(display) { snap in
                        HStack(spacing: 10) {
                          Image(systemName: snap.isPinned ? "pin.fill" : "clock")
                            .foregroundStyle(snap.isPinned ? .orange : .secondary)
                          VStack(alignment: .leading, spacing: 2) {
                            Text(snap.createdAtDisplay)
                            if let note = snap.note, !note.isEmpty {
                              Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            }
	                          }
	                          Spacer()
	                          Button(model.ui("Restore…", "恢复…")) { model.prepareRestoreSnapshot(snap) }
	                            .buttonStyle(.borderless)
	                            .disabled(!canOperateOnProjectFolder)
	                          Button(model.ui("Open", "打开")) { model.openSnapshotFolder(snap) }
	                            .buttonStyle(.borderless)
	                        }
	                      }
	                    }
	                    .frame(maxHeight: 260)
	                  }
	                } label: {
	                  Text(model.ui("Local snapshots (recent)", "本地快照（最近）"))
	                }

              case .logs:
                EmptyView()
              }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, 2)
          }
          .frame(minHeight: 0)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .layoutPriority(1)
        }
	      } else {
	        EmptyStateView(
	          title: model.ui("Select a project", "请选择一个项目"),
	          systemImage: "folder",
	          description: model.ui("Refresh the list, then select a project to see actions.", "先刷新列表，然后选择一个项目查看操作。")
	        )
	      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	    .confirmationDialog(
	      model.ui("Dry-run push", "预演推送"),
	      isPresented: $showDryRunConfirmation,
	      titleVisibility: .visible
	    ) {
	      Button(model.ui("Run dry-run", "运行预演")) { Task { await model.pushLocalFolder(dryRun: true) } }
	      Button(model.ui("Cancel", "取消"), role: .cancel) {}
	    } message: {
	      Text(model.ui("Dry-run will only list files that would be uploaded.", "预演只会列出将上传的文件，不会真正上传。"))
	    }
	    .confirmationDialog(
	      model.ui("Overwrite \(AppModel.configFileName)?", "覆盖 \(AppModel.configFileName)？"),
	      isPresented: Binding(
	        get: { model.overwritePrompt != nil },
	        set: { if !$0 { model.overwritePrompt = nil } }
	      ),
      titleVisibility: .visible,
      presenting: model.overwritePrompt
	    ) { prompt in
	      switch prompt.kind {
	      case .link:
	        Button(model.ui("Overwrite and Link", "覆盖并连接"), role: .destructive) {
	          Task { await model.confirmOverwriteLink(prompt) }
	          model.overwritePrompt = nil
	        }
	      case .create:
	        Button(model.ui("Overwrite and Create", "覆盖并创建"), role: .destructive) {
	          Task { await model.confirmOverwriteCreate(prompt) }
	          model.overwritePrompt = nil
	        }
	      }
	      Button(model.ui("Cancel", "取消"), role: .cancel) { model.overwritePrompt = nil }
	    } message: { prompt in
	      switch prompt.kind {
	      case .link:
	        let existing = prompt.existingProjectId ?? "(unknown)"
	        let target = prompt.targetProjectId ?? "(unknown)"
	        Text(
	          model.ui(
	            """
	            This folder already has .ol-sync.json (linked to project \(existing)).
	            We will first rename the existing .ol-sync.json to a timestamped .bak file, then link to project \(target).

	            If a watch is running for this folder, stop and restart it after re-linking.
	            """,
	            """
	            此文件夹已存在 .ol-sync.json（链接到项目 \(existing)）。
	            我们会先把现有的 .ol-sync.json 重命名为带时间戳的 .bak 文件，然后再连接到项目 \(target)。

	            如果该文件夹正在监听，请在重新连接后停止并重启监听。
	            """
	          )
	        )
	      case .create:
	        let existing = prompt.existingProjectId ?? "(unknown)"
	        Text(
	          model.ui(
	            """
	            This folder already has .ol-sync.json (linked to project \(existing)).
	            We will first rename the existing .ol-sync.json to a timestamped .bak file, then create a NEW remote project and link this folder to it.

	            This detaches the folder from the previous project (the old remote project is not deleted).
	            """,
	            """
	            此文件夹已存在 .ol-sync.json（链接到项目 \(existing)）。
	            我们会先把现有的 .ol-sync.json 重命名为带时间戳的 .bak 文件，然后创建一个新的远端项目，并把该文件夹连接到新项目。

	            这会让该文件夹与旧项目“解绑”（旧的远端项目不会被删除）。
	            """
	          )
	        )
	      }
	    }
	    .confirmationDialog(
	      model.ui("Apply remote changes?", "应用远端变更？"),
	      isPresented: Binding(
	        get: { model.remoteApplyPrompt != nil },
	        set: { if !$0 { model.remoteApplyPrompt = nil } }
	      ),
	      titleVisibility: .visible,
	      presenting: model.remoteApplyPrompt
	    ) { prompt in
	      Button(model.ui("Apply to local", "应用到本地"), role: .destructive) {
	        Task { await model.confirmApplyRemoteChanges(prompt) }
	        model.remoteApplyPrompt = nil
	      }
	      Button(model.ui("Cancel", "取消"), role: .cancel) { model.remoteApplyPrompt = nil }
	    } message: { prompt in
	      Text(
	        model.ui(
	          """
	          This will overwrite local files (last-write wins):
	          added=\(prompt.added), modified=\(prompt.modified), deleted=\(prompt.deleted)

	          Deleted files will NOT be deleted locally.
	          """,
	          """
	          这会覆盖本地文件（最后写入优先）：
	          新增=\(prompt.added)，修改=\(prompt.modified)，删除=\(prompt.deleted)

	          远端被删除的文件不会在本地被删除。
	          """
	        )
	      )
	    }
	    .confirmationDialog(
	      model.ui("Restore snapshot?", "恢复快照？"),
	      isPresented: Binding(
	        get: { model.snapshotRestorePrompt != nil },
	        set: { if !$0 { model.snapshotRestorePrompt = nil } }
	      ),
	      titleVisibility: .visible,
	      presenting: model.snapshotRestorePrompt
	    ) { prompt in
	      Button(model.ui("Restore to local (last-write wins)", "恢复到本地（最后写入优先）"), role: .destructive) {
	        Task { await model.confirmRestoreSnapshot(prompt) }
	        model.snapshotRestorePrompt = nil
	      }
	      Button(model.ui("Cancel", "取消"), role: .cancel) { model.snapshotRestorePrompt = nil }
	    } message: { _ in
	      Text(
	        model.ui(
	          """
	          This will overwrite local files from the snapshot.

	          Backups are stored under ~/.config/overleaf-sync/backups/.
	          Files not present in the snapshot will NOT be deleted locally.
	          """,
	          """
	          这会用快照内容覆盖本地文件。

	          备份保存在 ~/.config/overleaf-sync/backups/。
	          快照里不存在的文件不会在本地被删除。
	          """
	        )
	      )
	    }
	    .confirmationDialog(
	      model.ui("Move root .ol-sync.json aside?", "把根目录的 .ol-sync.json 挪开？"),
	      isPresented: Binding(
	        get: { model.rootConfigPrompt != nil },
	        set: { if !$0 { model.rootConfigPrompt = nil } }
	      ),
	      titleVisibility: .visible,
	      presenting: model.rootConfigPrompt
	    ) { prompt in
	      Button(model.ui("Move aside", "挪开"), role: .destructive) {
	        model.confirmMoveRootConfigAside(prompt)
	        model.rootConfigPrompt = nil
	      }
	      Button(model.ui("Cancel", "取消"), role: .cancel) { model.rootConfigPrompt = nil }
	    } message: { _ in
	      Text(
	        model.ui(
	          "This will rename the root .ol-sync.json to a timestamped .bak file (no deletion).",
	          "这会把根目录的 .ol-sync.json 重命名为带时间戳的 .bak 文件（不会删除）。"
	        )
	      )
	    }
    .sheet(item: $model.newFolderPrompt) { prompt in
      NewFolderSheet(prompt: prompt)
        .environmentObject(model)
    }
    .sheet(item: $model.projectDeletePrompt) { prompt in
      ProjectDeleteSheet(prompt: prompt)
        .environmentObject(model)
    }
  }
}

private struct RemoteCountBadge: View {
  let count: Int

  var body: some View {
    Text("\(count)")
      .font(.caption2)
      .foregroundStyle(.orange)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Capsule().fill(Color.orange.opacity(0.15)))
  }
}

private struct PressableLinkButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.tint)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.accentColor.opacity(configuration.isPressed ? 0.20 : 0.0))
      }
  }
}
