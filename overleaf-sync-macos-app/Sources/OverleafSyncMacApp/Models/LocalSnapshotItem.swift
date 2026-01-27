import Foundation

struct LocalSnapshotItem: Identifiable, Hashable, Sendable {
  let projectId: String
  let createdAt: Date?
  let note: String?
  let isPinned: Bool
  let dir: URL

  var id: String { dir.path }

  var createdAtDisplay: String {
    guard let createdAt else { return dir.lastPathComponent }
    return DateFormatter.localizedString(from: createdAt, dateStyle: .short, timeStyle: .short)
  }
}

