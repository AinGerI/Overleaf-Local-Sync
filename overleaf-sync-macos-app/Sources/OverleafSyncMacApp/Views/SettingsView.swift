import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Form {
      Section("Overleaf") {
        TextField("Base URL", text: $model.baseURL)
      }

      Section("Workspace") {
        HStack {
          Text(model.workspaceRoot?.path ?? "Not set")
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          Button("Choose…") { model.pickWorkspaceRoot() }
        }
      }

      Section("Login (optional)") {
        TextField("Email", text: $model.email)
        SecureField("Password (not saved)", text: $model.password)
        Button("Login") { Task { await model.login() } }
      }

      Section("Local folders") {
        HStack {
          Text("Local folder")
          Spacer()
          Text(model.localFolder?.path ?? "Not set")
            .lineLimit(1)
            .truncationMode(.middle)
          Button("Choose…") { model.pickLocalFolder() }
        }
        HStack {
          Text("Pull parent")
          Spacer()
          Text(model.pullParentFolder?.path ?? "Not set")
            .lineLimit(1)
            .truncationMode(.middle)
          Button("Choose…") { model.pickPullParentFolder() }
        }
      }
    }
    .padding()
    .frame(minWidth: 520)
  }
}
