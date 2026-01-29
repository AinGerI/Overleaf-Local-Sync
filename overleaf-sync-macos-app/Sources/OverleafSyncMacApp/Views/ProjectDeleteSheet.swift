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
	            Text(model.ui("Delete / Trash Project", "删除/移到废纸篓"))
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

	          GroupBox {
	            VStack(alignment: .leading, spacing: 8) {
	              Picker(model.ui("Action", "操作"), selection: $cloud) {
	                ForEach(CloudProjectDeletion.allCases) { action in
	                  Text(model.ui(action.titleEn, action.titleZh)).tag(action)
	                }
	              }
	              .pickerStyle(.radioGroup)

	              Text(
	                model.ui(
	                  "Move to Trash is reversible. Delete Permanently requires admin permission and cannot be undone.",
	                  "“移到废纸篓”可恢复；“永久删除”需要管理员权限且不可撤销。"
	                )
	              )
	                .font(.caption)
	                .foregroundStyle(.secondary)
	                .fixedSize(horizontal: false, vertical: true)
	            }
	          } label: {
	            Text(model.ui("Cloud", "云端"))
	          }

	          GroupBox {
	            VStack(alignment: .leading, spacing: 8) {
	              if let dir = prompt.linkedDir {
	                HStack {
	                  Text(dir.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
	                  Spacer()
	                  Button(model.ui("Open", "打开")) { NSWorkspace.shared.open(dir) }
	                }
	              } else {
	                Text(model.ui("No linked local folder found for this project.", "未找到该项目对应的已连接本地文件夹。"))
	                  .foregroundStyle(.secondary)
	              }

	              Picker(model.ui("Action", "操作"), selection: $local) {
	                ForEach(LocalProjectDeletion.allCases) { action in
	                  Text(model.ui(action.titleEn, action.titleZh)).tag(action)
	                }
	              }
	              .pickerStyle(.radioGroup)
	              .disabled(prompt.linkedDir == nil)

	              if prompt.linkedDir == nil {
	                Text(model.ui("Tip: link/pull this project first to enable local deletion.", "提示：请先连接/拉取该项目，以启用本地删除。"))
	                  .font(.caption)
	                  .foregroundStyle(.secondary)
	              }
	            }
	          } label: {
	            Text(model.ui("Local folder", "本地文件夹"))
	          }

	          GroupBox {
	            VStack(alignment: .leading, spacing: 8) {
	              Toggle(model.ui("Delete inbox batches (remote-change cache)", "删除收件箱批次（远端变更缓存）"), isOn: $deleteInbox)
	              Toggle(model.ui("Delete backups", "删除备份"), isOn: $deleteBackups)
	              Toggle(model.ui("Delete snapshots", "删除快照"), isOn: $deleteSnapshots)
	              Text(model.ui("Autowatch logs are kept.", "自动监听日志会保留。"))
	                .font(.caption)
	                .foregroundStyle(.secondary)
	            }
	          } label: {
	            Text(model.ui("Tool data (local only)", "工具数据（仅本地）"))
	          }

	          GroupBox {
	            VStack(alignment: .leading, spacing: 10) {
	              Text(model.ui("Type the project name to enable deletion:", "输入项目名称以启用删除："))
	                .font(.caption)
	                .foregroundStyle(.secondary)

	              TextField(model.ui("Project name", "项目名称"), text: $typedName)
	                .textFieldStyle(.roundedBorder)

	              if requiresPermanentAck {
	                Toggle(model.ui("I understand permanent deletion cannot be undone.", "我已知晓永久删除不可撤销。"), isOn: $acknowledgePermanent)
	              }

	              if missingLinkedFolder {
	                Text(model.ui("Local action requires a linked local folder.", "本地操作需要一个已连接的本地文件夹。"))
	                  .font(.caption)
	                  .foregroundStyle(.red)
	              } else if hasAnyAction && !nameMatches {
	                Text(model.ui("Project name does not match.", "项目名称不匹配。"))
	                  .font(.caption)
	                  .foregroundStyle(.red)
	              }
	            }
	          } label: {
	            Text(model.ui("Confirm", "确认"))
	          }
	        }
	        .padding()
	      }

	      Divider()

	      HStack {
	        Button(model.ui("Cancel", "取消"), role: .cancel) { dismiss() }
	        Spacer()
	        if isRunning {
	          ProgressView()
            .scaleEffect(0.8)
	        }
	        Button(model.ui("Run", "执行"), role: .destructive) {
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
