import AppKit
import SwiftUI

private enum ProjectDetailTab: String, CaseIterable, Hashable {
  case sync = "Sync"
  case remote = "Remote"
  case snapshots = "Snapshots"
  case logs = "Logs"
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
              Text("Copy ID")
            }
            .buttonStyle(PressableLinkButtonStyle())

            if copiedToastToken != nil {
              Label("Copied", systemImage: "checkmark")
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
            Text(tab.rawValue).tag(tab)
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
                GroupBox("Local folder") {
                  VStack(alignment: .leading, spacing: 8) {
                    HStack {
                      Text(model.localFolder?.path ?? "Not set")
                        .lineLimit(1)
                        .truncationMode(.middle)
                      Spacer()
                      Button("Choose…") { model.pickLocalFolder() }
                    }

                    if isProjectsRootSelected {
                      VStack(alignment: .leading, spacing: 6) {
                        Text("You selected the overleaf-projects root folder.")
                          .foregroundStyle(.red)
                        Text("Choose a specific project folder under overleaf-projects, e.g. overleaf-projects/报告撰写.")
                          .font(.caption)
                          .foregroundStyle(.secondary)
                        Button("Create a new local project…") {
                          if let root = model.projectsRoot {
                            model.newFolderPrompt = NewFolderPrompt(parent: root)
                          }
                        }
                        if let pid = cfgProjectId, !pid.isEmpty {
                          Text("This root folder currently contains .ol-sync.json linked to \(pid.prefix(8))…, which can cause confusing sync behavior.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                          Button("Fix: move root .ol-sync.json aside…") {
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
                          Text("This folder is linked to:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                          Text(linkedLabel)
                            .font(.caption)
                            .foregroundStyle(isLinkedToSelected ? .green : .orange)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        }

                        if !isLinkedToSelected {
                          Text("Selected project is different. Choose the correct folder for this project, or click Link to re-bind.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                      }
                    } else {
                      Text("Not linked yet (no .ol-sync.json).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                  }
                }

                GroupBox("Selected project link") {
                  if let dir = model.linkedFoldersByProjectId[project.id] {
                    HStack {
                      Text(dir.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                      Spacer()
                      Button("Use") { model.localFolder = dir }
                      Button("Start watch") {
                        model.localFolder = dir
                        model.startWatchForLocalFolder()
                      }
                    }
                  } else {
                    VStack(alignment: .leading, spacing: 6) {
                      Text("No linked local folder found under overleaf-projects.")
                        .foregroundStyle(.secondary)
                      Text("Tip: pull this project, or choose a folder and click Link once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                  }
                }

                HStack(spacing: 12) {
                  Button("Link") { Task { await model.linkSelectedProject() } }
                    .disabled(model.localFolder == nil || isProjectsRootSelected)
                  Button("Pull (download)") { Task { await model.pullSelectedProject() } }
                  Button("Create (from folder)") { Task { await model.createRemoteProjectFromLocalFolder() } }
                    .disabled(model.localFolder == nil)
                }

                GroupBox("Push") {
                  HStack {
                    Stepper(
                      value: $model.pushConcurrency,
                      in: 1...16,
                      step: 1,
                      label: { Text("Concurrency: \(model.pushConcurrency)") }
                    )
                    Spacer()
                    Button("Dry-run") { showDryRunConfirmation = true }
                      .disabled(!isLinkedToSelected)
                    Button("Push") { Task { await model.pushLocalFolder(dryRun: false) } }
                      .disabled(!isLinkedToSelected)
                  }
                }

                GroupBox("Watch") {
                  HStack {
                    Button("Start watch") { model.startWatchForLocalFolder() }
                      .disabled(!isLinkedToSelected)
                    Spacer()
                    if let dir = model.localFolder {
                      let internalRunning = model.watches.contains(where: { $0.dir == dir && $0.isRunning })
                      let externalRunning = model.externalWatches.contains(where: { $0.dir.standardizedFileURL == dir.standardizedFileURL })
                      if internalRunning || externalRunning {
                        Text("Running")
                          .foregroundStyle(.green)
                      }
                    }
                  }
                }

                GroupBox("Project actions") {
                  VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                      if project.archived {
                        Label("Archived", systemImage: "archivebox.fill")
                          .foregroundStyle(.orange)
                      }
                      if project.trashed {
                        Label("Trashed", systemImage: "trash.fill")
                          .foregroundStyle(.red)
                      }
                      if !project.archived && !project.trashed {
                        Text("Active")
                          .foregroundStyle(.secondary)
                      }
                      Spacer()
                    }

                    HStack(spacing: 12) {
                      if project.archived {
                        Button("Unarchive") { Task { await model.unarchiveSelectedProject() } }
                      } else {
                        Button("Archive") { Task { await model.archiveSelectedProject() } }
                      }

                      if project.trashed {
                        Button("Restore from Trash") { Task { await model.untrashSelectedProject() } }
                      }

                      Spacer()

                      Button("Delete / Trash…") { model.prepareDeleteSelectedProject() }
                        .tint(.red)
                    }

                    Text("Deletion supports cloud + local options and requires typing the project name. Autowatch logs are kept.")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                }

              case .remote:
                let canOperateOnProjectFolder = model.linkedFoldersByProjectId[project.id] != nil || isLinkedToSelected
                let pending = model.selectedProjectInboxBatches.filter { $0.state == .pending }
                let pendingCount = pending.count
                let pendingChanges = pending.reduce(0) { $0 + $1.changeCount }
                GroupBox("Remote changes") {
                  VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                      if pendingChanges > 0 {
                        RemoteCountBadge(count: pendingChanges)
                        Text(pendingCount == 1 ? "pending change(s) (1 batch)" : "pending change(s) (\(pendingCount) batches)")
                          .foregroundStyle(.secondary)
                      } else {
                        Text("No pending remote batches.")
                          .foregroundStyle(.secondary)
                      }
                      Spacer()
                      Button("Fetch now") { Task { await model.fetchRemoteChangesForSelectedProject() } }
                        .disabled(!canOperateOnProjectFolder)
                      Button("Apply latest…") { Task { await model.prepareApplyLatestRemoteChangesForSelectedProject() } }
                        .disabled(!canOperateOnProjectFolder)
                    }

                    Text("Auto-fetch runs every \(model.autoRemoteFetchIntervalMinutes) min (Settings → Remote changes).")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }

                GroupBox("Inbox (recent)") {
                  let batches = Array(model.selectedProjectInboxBatches.prefix(AppConstants.inboxKeepLastPerProject))
                  if batches.isEmpty {
                    Text("No inbox batches yet.")
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
                            Text("added=\(batch.addedCount), modified=\(batch.modifiedCount), deleted=\(batch.deletedCount)")
                              .font(.caption)
                              .foregroundStyle(.secondary)
                              .lineLimit(1)
                              .truncationMode(.tail)
                          }
                          Spacer()
                          if batch.state == .pending {
                            Button("Apply…") { model.prepareApplyInboxBatch(batch) }
                              .buttonStyle(.borderless)
                              .disabled(!canOperateOnProjectFolder)
                          } else {
                            Text("Applied")
                              .font(.caption)
                              .foregroundStyle(.secondary)
                          }
                          Button("Open") { model.openInboxBatchFolder(batch) }
                            .buttonStyle(.borderless)
                        }
                      }
                    }
                    .frame(maxHeight: 260)
                  }
                }

              case .snapshots:
                let canOperateOnProjectFolder = model.linkedFoldersByProjectId[project.id] != nil || isLinkedToSelected
                GroupBox("Snapshots") {
                  VStack(alignment: .leading, spacing: 8) {
                    Text("Snapshots are manual checkpoints. Auto snapshots can be cleaned up (keep last 5). Pinned snapshots are kept forever.")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                      .truncationMode(.tail)
                      .frame(maxWidth: .infinity, alignment: .leading)
                      .help("Auto snapshots are eligible for cleanup (keep last 5 per project). Pinned snapshots are kept forever.")

                    HStack(spacing: 12) {
                      Button("Save snapshot") { Task { await model.saveAutoSnapshotForSelectedProject() } }
                        .disabled(!canOperateOnProjectFolder)
                      Button("Pin snapshot") { Task { await model.savePinnedSnapshotForSelectedProject() } }
                        .disabled(!canOperateOnProjectFolder)
                      Button("Open snapshots") { model.openSnapshotsFolderForSelectedProject() }
                        .disabled(!canOperateOnProjectFolder)
                      Spacer()
                    }
                  }
                }

                GroupBox("Local snapshots (recent)") {
                  let pinned = model.selectedProjectSnapshots.filter { $0.isPinned }
                  let auto = model.selectedProjectSnapshots.filter { !$0.isPinned }
                  let recentAuto = Array(auto.prefix(AppConstants.autoSnapshotKeepLastPerProject))
                  let display = pinned + recentAuto

                  if display.isEmpty {
                    Text("No snapshots yet.")
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
                          Button("Restore…") { model.prepareRestoreSnapshot(snap) }
                            .buttonStyle(.borderless)
                            .disabled(!canOperateOnProjectFolder)
                          Button("Open") { model.openSnapshotFolder(snap) }
                            .buttonStyle(.borderless)
                        }
                      }
                    }
                    .frame(maxHeight: 260)
                  }
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
          title: "Select a project",
          systemImage: "folder",
          description: "Refresh the list, then select a project to see actions."
        )
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .confirmationDialog(
      "Dry-run push",
      isPresented: $showDryRunConfirmation,
      titleVisibility: .visible
    ) {
      Button("Run dry-run") { Task { await model.pushLocalFolder(dryRun: true) } }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Dry-run will only list files that would be uploaded.")
    }
    .confirmationDialog(
      "Overwrite \(AppModel.configFileName)?",
      isPresented: Binding(
        get: { model.overwritePrompt != nil },
        set: { if !$0 { model.overwritePrompt = nil } }
      ),
      titleVisibility: .visible,
      presenting: model.overwritePrompt
    ) { prompt in
      switch prompt.kind {
      case .link:
        Button("Overwrite and Link", role: .destructive) {
          Task { await model.confirmOverwriteLink(prompt) }
          model.overwritePrompt = nil
        }
      case .create:
        Button("Overwrite and Create", role: .destructive) {
          Task { await model.confirmOverwriteCreate(prompt) }
          model.overwritePrompt = nil
        }
      }
      Button("Cancel", role: .cancel) { model.overwritePrompt = nil }
    } message: { prompt in
      switch prompt.kind {
      case .link:
        let existing = prompt.existingProjectId ?? "(unknown)"
        let target = prompt.targetProjectId ?? "(unknown)"
        Text(
          """
          This folder already has .ol-sync.json (linked to project \(existing)).
          We will first rename the existing .ol-sync.json to a timestamped .bak file, then link to project \(target).

          If a watch is running for this folder, stop and restart it after re-linking.
          """
        )
      case .create:
        let existing = prompt.existingProjectId ?? "(unknown)"
        Text(
          """
          This folder already has .ol-sync.json (linked to project \(existing)).
          We will first rename the existing .ol-sync.json to a timestamped .bak file, then create a NEW remote project and link this folder to it.

          This detaches the folder from the previous project (the old remote project is not deleted).
          """
        )
      }
    }
    .confirmationDialog(
      "Apply remote changes?",
      isPresented: Binding(
        get: { model.remoteApplyPrompt != nil },
        set: { if !$0 { model.remoteApplyPrompt = nil } }
      ),
      titleVisibility: .visible,
      presenting: model.remoteApplyPrompt
    ) { prompt in
      Button("Apply to local", role: .destructive) {
        Task { await model.confirmApplyRemoteChanges(prompt) }
        model.remoteApplyPrompt = nil
      }
      Button("Cancel", role: .cancel) { model.remoteApplyPrompt = nil }
    } message: { prompt in
      Text(
        """
        This will overwrite local files (last-write wins):
        added=\(prompt.added), modified=\(prompt.modified), deleted=\(prompt.deleted)

        Deleted files will NOT be deleted locally.
        """
      )
    }
    .confirmationDialog(
      "Restore snapshot?",
      isPresented: Binding(
        get: { model.snapshotRestorePrompt != nil },
        set: { if !$0 { model.snapshotRestorePrompt = nil } }
      ),
      titleVisibility: .visible,
      presenting: model.snapshotRestorePrompt
    ) { prompt in
      Button("Restore to local (last-write wins)", role: .destructive) {
        Task { await model.confirmRestoreSnapshot(prompt) }
        model.snapshotRestorePrompt = nil
      }
      Button("Cancel", role: .cancel) { model.snapshotRestorePrompt = nil }
    } message: { _ in
      Text(
        """
        This will overwrite local files from the snapshot.

        Backups are stored under ~/.config/overleaf-sync/backups/.
        Files not present in the snapshot will NOT be deleted locally.
        """
      )
    }
    .confirmationDialog(
      "Move root .ol-sync.json aside?",
      isPresented: Binding(
        get: { model.rootConfigPrompt != nil },
        set: { if !$0 { model.rootConfigPrompt = nil } }
      ),
      titleVisibility: .visible,
      presenting: model.rootConfigPrompt
    ) { prompt in
      Button("Move aside", role: .destructive) {
        model.confirmMoveRootConfigAside(prompt)
        model.rootConfigPrompt = nil
      }
      Button("Cancel", role: .cancel) { model.rootConfigPrompt = nil }
    } message: { _ in
      Text("This will rename the root .ol-sync.json to a timestamped .bak file (no deletion).")
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
