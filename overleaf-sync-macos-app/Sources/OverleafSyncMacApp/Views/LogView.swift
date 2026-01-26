import SwiftUI

struct LogView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        Text(model.logText.isEmpty ? "No logs yet." : model.logText)
          .frame(maxWidth: .infinity, alignment: .leading)
          .font(.system(.footnote, design: .monospaced))
          .textSelection(.enabled)
          .id("BOTTOM")
      }
      .onChange(of: model.logText) { _ in
        proxy.scrollTo("BOTTOM", anchor: .bottom)
      }
    }
  }
}
