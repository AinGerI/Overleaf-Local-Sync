import SwiftUI

struct WatchListView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Button("Refresh") { Task { await model.refreshExternalWatches() } }
        Button("Watch all linked") { model.startWatchAllLinkedProjects() }
        Spacer()
      }

      if model.watches.isEmpty && model.externalWatches.isEmpty {
        EmptyStateView(
          title: "No active watches",
          systemImage: "eye.slash",
          description: "Start a watch from the Projects detail pane, or run ./start.sh to auto-watch all linked folders."
        )
      } else {
        List(selection: $model.selectedWatchSelection) {
          if !model.externalWatches.isEmpty {
            Section("External") {
              ForEach(model.externalWatches) { w in
                HStack {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(w.title)
                    Text(w.dir.path)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                      .truncationMode(.middle)
                  }
                  Spacer()
                  let isDuplicate = w.pids.count > 1
                  Text(isDuplicate ? "Running (\(w.pids.count))" : "Running")
                    .foregroundStyle(isDuplicate ? .orange : .green)
                }
                .tag(WatchSelection.external(w.id))
              }
            }
          }

          if !model.watches.isEmpty {
            Section("App") {
              ForEach(model.watches) { w in
                HStack {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(w.title)
                    Text(w.dir.path)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                      .truncationMode(.middle)
                  }
                  Spacer()
                  Text(w.isRunning ? "Running" : "Stopped")
                    .foregroundStyle(w.isRunning ? .green : .secondary)
                }
                .tag(WatchSelection.internal(w.id))
              }
            }
          }
        }
      }
    }
    .padding()
    .task { await model.refreshExternalWatches() }
  }
}
