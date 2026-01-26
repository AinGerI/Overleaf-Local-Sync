import SwiftUI

struct LoginSheet: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Login required")
        .font(.title2)
        .bold()
      Text("This app runs the Node CLI in non-interactive mode, so it cannot prompt in a terminal. Provide your credentials once to cache a session.")
        .foregroundStyle(.secondary)

      Form {
        TextField("Email", text: $model.email)
        SecureField("Password (not saved)", text: $model.password)
      }

      HStack {
        Button("Cancel") {
          model.password = ""
          model.showLoginSheet = false
        }
        Spacer()
        Button("Login") { Task { await model.login() } }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding()
    .frame(width: 520)
  }
}
