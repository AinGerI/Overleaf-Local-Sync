import SwiftUI

struct WatchDetailView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let w = model.selectedWatch {
        HStack {
          Text(w.dir.path)
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          Button("Stop") { w.stop() }
            .disabled(!w.isRunning)
        }

        ScrollViewReader { proxy in
          ScrollView {
            Text(w.output)
              .frame(maxWidth: .infinity, alignment: .leading)
              .font(.system(.footnote, design: .monospaced))
              .textSelection(.enabled)
              .id("BOTTOM")
          }
          .onChange(of: w.output) { _ in
            proxy.scrollTo("BOTTOM", anchor: .bottom)
          }
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
