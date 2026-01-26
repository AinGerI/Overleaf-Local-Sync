import SwiftUI

struct ProjectDetailView: View {
  @EnvironmentObject private var model: AppModel
  @State private var showDryRunConfirmation: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let project = model.selectedProject {
        let cfgProjectId = model.localFolderConfig?.projectId
        let isProjectsRootSelected = model.projectsRoot != nil && model.localFolder == model.projectsRoot
        let isLinkedToSelected = !isProjectsRootSelected && (cfgProjectId == project.id)

        VStack(alignment: .leading, spacing: 6) {
          Text(project.name).font(.title2).bold()
          Text(project.id).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary)
        }

        Divider()

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
                  Text("This root folder currently contains .ol-sync.json linked to \(pid), which can cause confusing sync behavior.")
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
              let linkedLabel = linkedName.map { "\($0) (\(cfgProjectId))" } ?? cfgProjectId

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
            if let w = model.watches.first(where: { $0.dir == model.localFolder }) {
              Text(w.isRunning ? "Running" : "Stopped")
                .foregroundStyle(w.isRunning ? .green : .secondary)
            }
          }
        }

        GroupBox("Remote changes") {
          VStack(alignment: .leading, spacing: 8) {
            if let manifest = model.remoteManifest, manifest.projectId == project.id {
              Text("Last fetched batch: \(manifest.batchId)")
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(
                "added=\(manifest.changes.added.count), modified=\(manifest.changes.modified.count), deleted=\(manifest.changes.deleted.count)"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            } else {
              Text("Fetch remote changes when you want to apply edits made on the web UI.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
              Button("Fetch") { Task { await model.fetchRemoteChanges() } }
                .disabled(!isLinkedToSelected)
              Button("Apply (last-write wins)…") { Task { await model.prepareApplyRemoteChanges() } }
                .disabled(!isLinkedToSelected)
            }

            Text("Apply will overwrite local files that changed on remote. Backups are stored under ~/.config/overleaf-sync/backups/.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Divider()
        LogView()
      } else {
        EmptyStateView(
          title: "Select a project",
          systemImage: "folder",
          description: "Refresh the list, then select a project to see actions."
        )
      }
    }
    .padding()
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
  }
}
