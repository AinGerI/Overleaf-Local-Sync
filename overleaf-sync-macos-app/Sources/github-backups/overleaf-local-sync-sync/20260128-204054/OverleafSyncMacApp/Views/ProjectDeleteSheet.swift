import AppKit
import SwiftUI

struct ProjectDeleteSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss

  let prompt: ProjectDeletePrompt

  @State private var cloud: CloudProjectDeletion
  @State private var local: LocalProjectDeletion = .none
  @State private var deleteInbox: Bool = false
  @State private var deleteBackups: Bool = false
  @State private var deleteSnapshots: Bool = false
  @State private var typedName: String = ""
  @State private var acknowledgePermanent: Bool = false
  @State private var isRunning: Bool = false

  init(prompt: ProjectDeletePrompt) {
    self.prompt = prompt
    _cloud = State(initialValue: prompt.trashed ? .none : .moveToTrash)
  }

  private var nameMatches: Bool {
    typedName.trimmingCharacters(in: .whitespacesAndNewlines) == prompt.projectName
  }

  private var hasAnyAction: Bool {
    cloud != .none || local != .none || deleteInbox || deleteBackups || deleteSnapshots
  }

  private var needsLinkedFolder: Bool {
    local != .none
  }

  private var missingLinkedFolder: Bool {
    needsLinkedFolder && prompt.linkedDir == nil
  }

  private var requiresPermanentAck: Bool {
    cloud.isPermanent || local.isPermanent
  }

  private var canRun: Bool {
    hasAnyAction && nameMatches && !missingLinkedFolder && (!requiresPermanentAck || acknowledgePermanent) && !isRunning
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Delete / Trash Project")
              .font(.title2)
              .bold()
            Text(prompt.projectName)
              .font(.headline)
            Text(prompt.projectId)
              .font(.system(.footnote, design: .monospaced))
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
              .lineLimit(1)
              .truncationMode(.middle)
          }

          Divider()

          GroupBox("Cloud") {
            VStack(alignment: .leading, spacing: 8) {
              Picker("Action", selection: $cloud) {
                ForEach(CloudProjectDeletion.allCases) { action in
                  Text(action.rawValue).tag(action)
                }
              }
              .pickerStyle(.radioGroup)

              Text("Move to Trash is reversible. Delete Permanently requires admin permission and cannot be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }

          GroupBox("Local folder") {
            VStack(alignment: .leading, spacing: 8) {
              if let dir = prompt.linkedDir {
                HStack {
                  Text(dir.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                  Spacer()
                  Button("Open") { NSWorkspace.shared.open(dir) }
                }
              } else {
                Text("No linked local folder found for this project.")
                  .foregroundStyle(.secondary)
              }

              Picker("Action", selection: $local) {
                ForEach(LocalProjectDeletion.allCases) { action in
                  Text(action.rawValue).tag(action)
                }
              }
              .pickerStyle(.radioGroup)
              .disabled(prompt.linkedDir == nil)

              if prompt.linkedDir == nil {
                Text("Tip: link/pull this project first to enable local deletion.")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }

          GroupBox("Tool data (local only)") {
            VStack(alignment: .leading, spacing: 8) {
              Toggle("Delete inbox batches (remote-change cache)", isOn: $deleteInbox)
              Toggle("Delete backups", isOn: $deleteBackups)
              Toggle("Delete snapshots", isOn: $deleteSnapshots)
              Text("Autowatch logs are kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          GroupBox("Confirm") {
            VStack(alignment: .leading, spacing: 10) {
              Text("Type the project name to enable deletion:")
                .font(.caption)
                .foregroundStyle(.secondary)

              TextField("Project name", text: $typedName)
                .textFieldStyle(.roundedBorder)

              if requiresPermanentAck {
                Toggle("I understand permanent deletion cannot be undone.", isOn: $acknowledgePermanent)
              }

              if missingLinkedFolder {
                Text("Local action requires a linked local folder.")
                  .font(.caption)
                  .foregroundStyle(.red)
              } else if hasAnyAction && !nameMatches {
                Text("Project name does not match.")
                  .font(.caption)
                  .foregroundStyle(.red)
              }
            }
          }
        }
        .padding()
      }

      Divider()

      HStack {
        Button("Cancel", role: .cancel) { dismiss() }
        Spacer()
        if isRunning {
          ProgressView()
            .scaleEffect(0.8)
        }
        Button("Run", role: .destructive) {
          isRunning = true
          Task { @MainActor in
            await model.deleteProject(
              prompt: prompt,
              cloud: cloud,
              local: local,
              deleteInbox: deleteInbox,
              deleteBackups: deleteBackups,
              deleteSnapshots: deleteSnapshots
            )
            isRunning = false
            dismiss()
          }
        }
        .disabled(!canRun)
      }
      .padding()
    }
    .frame(width: 620, height: 580)
  }
}
