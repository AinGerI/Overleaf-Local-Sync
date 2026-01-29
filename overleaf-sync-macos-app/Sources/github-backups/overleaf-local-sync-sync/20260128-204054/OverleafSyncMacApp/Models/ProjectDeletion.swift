import Foundation

enum CloudProjectDeletion: String, CaseIterable, Hashable, Identifiable {
  case none = "None"
  case moveToTrash = "Move to Trash"
  case permanentlyDelete = "Delete Permanently"

  var id: String { rawValue }

  var isDestructive: Bool { self != .none }
  var isPermanent: Bool { self == .permanentlyDelete }
}

enum LocalProjectDeletion: String, CaseIterable, Hashable, Identifiable {
  case none = "None"
  case moveToTrash = "Move to Trash"
  case permanentlyDelete = "Delete Permanently"

  var id: String { rawValue }

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

