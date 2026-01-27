import AppKit
import SwiftUI

struct ProjectListView: View {
  @EnvironmentObject private var model: AppModel
  @State private var copiedToastToken: UUID? = nil
  @State private var showIdColumn: Bool = Preferences.getBool(forKey: Preferences.Key.projectsShowIdColumn) ?? false
  @State private var showLocalColumn: Bool = Preferences.getBool(forKey: Preferences.Key.projectsShowLocalColumn) ?? true
  @State private var showRemoteColumn: Bool = Preferences.getBool(forKey: Preferences.Key.projectsShowRemoteColumn) ?? true
  @State private var showAccessColumn: Bool = Preferences.getBool(forKey: Preferences.Key.projectsShowAccessColumn) ?? true
  @State private var showUpdatedColumn: Bool = Preferences.getBool(forKey: Preferences.Key.projectsShowUpdatedColumn) ?? true
  @State private var showByColumn: Bool = Preferences.getBool(forKey: Preferences.Key.projectsShowByColumn) ?? true
  
  private var columnsKey: String {
    [
      showIdColumn,
      showLocalColumn,
      showRemoteColumn,
      showAccessColumn,
      showUpdatedColumn,
      showByColumn,
    ]
    .map { $0 ? "1" : "0" }
    .joined()
  }

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
        Menu {
          Toggle("ID", isOn: $showIdColumn)
          Toggle("Local", isOn: $showLocalColumn)
          Toggle("Remote", isOn: $showRemoteColumn)
          Toggle("Access", isOn: $showAccessColumn)
          Toggle("Updated", isOn: $showUpdatedColumn)
          Toggle("By", isOn: $showByColumn)
        } label: {
          Label("Columns", systemImage: "slider.horizontal.3")
        }
        .fixedSize()

        Button {
          let ids = model.projects.map { $0.id }.joined(separator: "\n")
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(ids, forType: .string)

          let token = UUID()
          copiedToastToken = token
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if copiedToastToken == token {
              copiedToastToken = nil
            }
          }
        } label: {
          Label("Copy all IDs", systemImage: "doc.on.doc")
        }
        .tint(copiedToastToken != nil ? .green : .accentColor)
        .disabled(model.projects.isEmpty)
        Button("Choose…") { model.pickWorkspaceRoot() }
        Button("Refresh") { Task { await model.refreshProjects() } }
          .disabled(model.workspaceRoot == nil)
      }
      .animation(.easeInOut(duration: 0.15), value: copiedToastToken != nil)
      .onChange(of: showIdColumn) { _ in Preferences.setBool(showIdColumn, forKey: Preferences.Key.projectsShowIdColumn) }
      .onChange(of: showLocalColumn) { _ in Preferences.setBool(showLocalColumn, forKey: Preferences.Key.projectsShowLocalColumn) }
      .onChange(of: showRemoteColumn) { _ in Preferences.setBool(showRemoteColumn, forKey: Preferences.Key.projectsShowRemoteColumn) }
      .onChange(of: showAccessColumn) { _ in Preferences.setBool(showAccessColumn, forKey: Preferences.Key.projectsShowAccessColumn) }
      .onChange(of: showUpdatedColumn) { _ in Preferences.setBool(showUpdatedColumn, forKey: Preferences.Key.projectsShowUpdatedColumn) }
      .onChange(of: showByColumn) { _ in Preferences.setBool(showByColumn, forKey: Preferences.Key.projectsShowByColumn) }

      if model.workspaceRoot == nil {
        EmptyStateView(
          title: "Choose a workspace root",
          systemImage: "folder.badge.plus",
          description: "Select the repository root that contains overleaf-sync/ol-sync.mjs."
        )
      } else {
        Table(model.projects, selection: $model.selectedProjectId) {
          TableColumn("Name") { p in Text(p.name) }

          TableColumn("ID") { p in
            Text(p.id)
              .font(.system(.caption, design: .monospaced))
              .lineLimit(1)
              .truncationMode(.middle)
              .help(p.id)
          }
          .width(
            min: showIdColumn ? 140 : 0,
            ideal: showIdColumn ? 220 : 0,
            max: showIdColumn ? .infinity : 0
          )

          TableColumn("Local") { p in
            if model.linkedFoldersByProjectId[p.id] != nil {
              Image(systemName: "link")
                .foregroundStyle(.green)
            } else {
              Text("")
            }
          }
          .width(min: showLocalColumn ? 44 : 0, ideal: showLocalColumn ? 56 : 0, max: showLocalColumn ? 80 : 0)

          TableColumn("Remote") { p in
            let pendingChanges = model.pendingRemoteChangeCount(for: p.id)
            if pendingChanges > 0 {
              Text("\(pendingChanges)")
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
                .help("\(pendingChanges) pending remote change(s)")
            } else {
              Text("")
            }
          }
          .width(min: showRemoteColumn ? 60 : 0, ideal: showRemoteColumn ? 80 : 0, max: showRemoteColumn ? 120 : 0)

          TableColumn("Access") { p in Text(p.accessLevel) }
            .width(min: showAccessColumn ? 60 : 0, ideal: showAccessColumn ? 70 : 0, max: showAccessColumn ? 120 : 0)

          TableColumn("Updated") { p in Text(p.lastUpdatedDisplay) }
            .width(min: showUpdatedColumn ? 120 : 0, ideal: showUpdatedColumn ? 140 : 0, max: showUpdatedColumn ? 220 : 0)

          TableColumn("By") { p in Text(p.lastUpdatedBy ?? "") }
            .width(min: showByColumn ? 120 : 0, ideal: showByColumn ? 160 : 0, max: showByColumn ? .infinity : 0)
        }
        .id(columnsKey)
      }
    }
    .padding()
  }
}
