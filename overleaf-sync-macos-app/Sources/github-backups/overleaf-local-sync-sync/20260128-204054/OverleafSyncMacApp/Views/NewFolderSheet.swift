import SwiftUI

struct NewFolderSheet: View {
  @EnvironmentObject private var model: AppModel
  let prompt: NewFolderPrompt

  @State private var name: String = ""
  @State private var startWatch: Bool = true

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Create a new local project")
        .font(.title2)
        .bold()

      Text("A new folder will be created under:")
        .foregroundStyle(.secondary)
      Text(prompt.parent.path)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

      Form {
        TextField("Project name", text: $name)
        Toggle("Start watch after create", isOn: $startWatch)
      }

      HStack {
        Button("Cancel") { model.newFolderPrompt = nil }
        Spacer()
        Button("Create") {
          Task { await model.confirmCreateNewFolder(prompt, name: name, startWatchAfterCreate: startWatch) }
          model.newFolderPrompt = nil
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding()
    .frame(width: 520)
  }
}
