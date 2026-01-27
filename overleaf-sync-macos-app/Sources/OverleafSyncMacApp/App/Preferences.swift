import Foundation

enum Preferences {
  enum Key {
    static let workspaceRoot = "workspaceRoot"
    static let baseURL = "baseURL"
    static let email = "email"
    static let localFolder = "localFolder"
    static let pullParentFolder = "pullParentFolder"
    static let autoRemoteFetchEnabled = "autoRemoteFetchEnabled"
    static let autoRemoteFetchIntervalMinutes = "autoRemoteFetchIntervalMinutes"

    static let projectsShowIdColumn = "projectsShowIdColumn"
    static let projectsShowLocalColumn = "projectsShowLocalColumn"
    static let projectsShowRemoteColumn = "projectsShowRemoteColumn"
    static let projectsShowAccessColumn = "projectsShowAccessColumn"
    static let projectsShowUpdatedColumn = "projectsShowUpdatedColumn"
    static let projectsShowByColumn = "projectsShowByColumn"
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

  static func getBool(forKey key: String) -> Bool? {
    guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
    return UserDefaults.standard.bool(forKey: key)
  }

  static func setBool(_ value: Bool, forKey key: String) {
    UserDefaults.standard.set(value, forKey: key)
  }

  static func getInt(forKey key: String) -> Int? {
    guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
    return UserDefaults.standard.integer(forKey: key)
  }

  static func setInt(_ value: Int, forKey key: String) {
    UserDefaults.standard.set(value, forKey: key)
  }
}
