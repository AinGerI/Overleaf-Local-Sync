import Foundation

enum Preferences {
  enum Key {
    static let workspaceRoot = "workspaceRoot"
    static let baseURL = "baseURL"
    static let email = "email"
    static let localFolder = "localFolder"
    static let pullParentFolder = "pullParentFolder"
  }

  static func getString(forKey key: String) -> String? {
    UserDefaults.standard.string(forKey: key)
  }

  static func setString(_ value: String, forKey key: String) {
    UserDefaults.standard.set(value, forKey: key)
  }

  static func getPath(forKey key: String) -> URL? {
    guard let s = UserDefaults.standard.string(forKey: key), !s.isEmpty else { return nil }
    return URL(fileURLWithPath: s)
  }

  static func setPath(_ value: URL?, forKey key: String) {
    UserDefaults.standard.set(value?.path ?? "", forKey: key)
  }
}

