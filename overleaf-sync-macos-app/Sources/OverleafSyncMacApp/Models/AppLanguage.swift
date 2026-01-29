import Foundation

enum AppLanguage: String, CaseIterable, Hashable, Identifiable {
  case english = "en"
  case chinese = "zh-Hans"

  var id: String { rawValue }

  var label: String {
    switch self {
    case .english: "English"
    case .chinese: "中文"
    }
  }

  static func defaultForSystem() -> AppLanguage {
    let preferred = Locale.preferredLanguages.first ?? ""
    if preferred.hasPrefix("zh") { return .chinese }
    return .english
  }
}

