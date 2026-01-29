import SwiftUI

struct WatchDetailView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let watch = model.selectedWatch {
        HStack {
          Text(watch.dir.path)
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          Button("Stop") { watch.stop() }
            .disabled(!watch.isRunning)
        }

        ScrollViewReader { proxy in
          ScrollView {
            Text(watch.output)
              .frame(maxWidth: .infinity, alignment: .leading)
              .font(.system(.footnote, design: .monospaced))
              .textSelection(.enabled)
              .id("BOTTOM")
          }
          .onChange(of: watch.output) { _ in
            proxy.scrollTo("BOTTOM", anchor: .bottom)
          }
        }
      } else if let watch = model.selectedExternalWatch {
        VStack(alignment: .leading, spacing: 10) {
          Text(watch.dir.path)
            .lineLimit(1)
            .truncationMode(.middle)

          Text("External watch process (started outside the app).")
            .font(.caption)
            .foregroundStyle(.secondary)

          Text("PIDs: \(watch.pids.map(String.init).joined(separator: ", "))")
            .font(.caption)
            .foregroundStyle(.secondary)

          HStack(spacing: 12) {
            Button("Stop") { model.stopExternalWatch(watch) }
            if watch.pids.count > 1 {
              Button("Deduplicate") { model.dedupeExternalWatch(watch) }
            }
            Button("Open logs folder") { model.openExternalWatchLogs(watch) }
            Spacer()
          }

          Text("Tip: If this watch was started by ./start.sh, logs are under ~/.config/overleaf-sync/autowatch/…")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else {
        EmptyStateView(
          title: "Select a watch",
          systemImage: "eye",
          description: "Choose a watch from the list to view its output."
        )
      }
    }
    .padding()
  }
}
