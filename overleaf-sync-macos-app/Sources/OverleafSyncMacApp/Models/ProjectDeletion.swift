import Foundation

enum CloudProjectDeletion: String, CaseIterable, Hashable, Identifiable {
  case none = "None"
  case moveToTrash = "Move to Trash"
  case permanentlyDelete = "Delete Permanently"

  var id: String { rawValue }

  var titleEn: String { rawValue }

  var titleZh: String {
    switch self {
    case .none: "无"
    case .moveToTrash: "移到废纸篓"
    case .permanentlyDelete: "永久删除"
    }
  }

  var isDestructive: Bool { self != .none }
  var isPermanent: Bool { self == .permanentlyDelete }
}

enum LocalProjectDeletion: String, CaseIterable, Hashable, Identifiable {
  case none = "None"
  case moveToTrash = "Move to Trash"
  case permanentlyDelete = "Delete Permanently"

  var id: String { rawValue }

  var titleEn: String { rawValue }

  var titleZh: String {
    switch self {
    case .none: "无"
    case .moveToTrash: "移到废纸篓"
    case .permanentlyDelete: "永久删除"
    }
  }

  var isDestructive: Bool { self != .none }
  var isPermanent: Bool { self == .permanentlyDelete }
}

struct ProjectDeletePrompt: Identifiable, Hashable {
  let id = UUID()
  let projectId: String
  let projectName: String
  let archived: Bool
  let trashed: Bool
  let linkedDir: URL?
  let effectiveBaseURL: String
}
