import SwiftUI

struct ProjectListView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Workspace (repo root)")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(model.workspaceRoot?.path ?? "Not set")
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer()
        Button("Choose…") { model.pickWorkspaceRoot() }
        Button("Refresh") { Task { await model.refreshProjects() } }
          .disabled(model.workspaceRoot == nil)
      }

      if model.workspaceRoot == nil {
        EmptyStateView(
          title: "Choose a workspace root",
          systemImage: "folder.badge.plus",
          description: "Select the repository root that contains overleaf-sync/ol-sync.mjs."
        )
      } else {
        Table(model.projects, selection: $model.selectedProjectId) {
          TableColumn("Name") { p in Text(p.name) }
          TableColumn("Local") { p in
            if model.linkedFoldersByProjectId[p.id] != nil {
              Image(systemName: "link")
                .foregroundStyle(.green)
            } else {
              Text("")
            }
          }
          TableColumn("Access") { p in Text(p.accessLevel) }
          TableColumn("Updated") { p in Text(p.lastUpdatedDisplay) }
          TableColumn("By") { p in Text(p.lastUpdatedBy ?? "") }
          TableColumn("ID") { p in Text(p.id).font(.system(.footnote, design: .monospaced)) }
        }
      }
    }
    .padding()
  }
}
