import SwiftUI

struct LoginSheet: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(model.ui("Login required", "需要登录"))
        .font(.title2)
        .bold()
      Text(
        model.ui(
          "This app runs the Node CLI in non-interactive mode, so it cannot prompt in a terminal. Provide your credentials once to cache a session.",
          "本应用以非交互模式运行 Node CLI，无法在终端里弹出提示。请提供一次账号信息以缓存会话。"
        )
      )
        .foregroundStyle(.secondary)

      Form {
        TextField(model.ui("Email", "邮箱"), text: $model.email)
        SecureField(model.ui("Password (not saved)", "密码（不保存）"), text: $model.password)
      }

      HStack {
        Button(model.ui("Cancel", "取消")) {
          model.password = ""
          model.showLoginSheet = false
        }
        Spacer()
        Button(model.ui("Login", "登录")) { Task { await model.login() } }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding()
    .frame(width: 520)
  }
}
