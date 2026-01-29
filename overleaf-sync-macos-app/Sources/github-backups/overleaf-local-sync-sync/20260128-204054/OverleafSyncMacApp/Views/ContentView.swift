import SwiftUI

enum SidebarItem: String, CaseIterable, Hashable, Identifiable {
  case projects
  case watches
  case settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .projects: "Projects"
    case .watches: "Watches"
    case .settings: "Settings"
    }
  }

  var systemImage: String {
    switch self {
    case .projects: "folder"
    case .watches: "eye"
    case .settings: "gearshape"
    }
  }
}

struct ContentView: View {
  @EnvironmentObject private var model: AppModel
  @State private var sidebarSelection: SidebarItem = .projects

  var body: some View {
    NavigationSplitView {
      List(selection: $sidebarSelection) {
        ForEach(SidebarItem.allCases) { item in
          Label(item.title, systemImage: item.systemImage)
            .tag(item)
        }
      }
      .navigationTitle("Overleaf Local Sync")
      .listStyle(.sidebar)
    } content: {
      switch sidebarSelection {
      case .projects:
        ProjectListView()
      case .watches:
        WatchListView()
      case .settings:
        SettingsView()
      }
    } detail: {
      switch sidebarSelection {
      case .projects:
        ProjectDetailView()
      case .watches:
        WatchDetailView()
      case .settings:
        LogView()
      }
    }
    .background(WindowConfigurator(minContentSize: NSSize(width: 860, height: 520)))
    .alert(item: $model.alert) { alert in
      Alert(title: Text(alert.title), message: Text(alert.message))
    }
    .sheet(isPresented: $model.showLoginSheet) {
      LoginSheet()
        .environmentObject(model)
    }
  }
}
