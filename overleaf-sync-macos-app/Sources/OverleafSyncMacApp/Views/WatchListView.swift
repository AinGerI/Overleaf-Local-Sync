import SwiftUI

struct WatchListView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Button("Watch all linked") { model.startWatchAllLinkedProjects() }
        Spacer()
      }

      if model.watches.isEmpty {
        EmptyStateView(
          title: "No active watches",
          systemImage: "eye.slash",
          description: "Start a watch from the Projects detail pane."
        )
      } else {
        List(selection: $model.selectedWatchId) {
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
            .tag(w.id)
          }
        }
      }
    }
    .padding()
  }
}
