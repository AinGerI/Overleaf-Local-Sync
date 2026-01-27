import Foundation

struct RemoteInboxBatch: Identifiable, Hashable, Sendable {
  enum State: String, Hashable, Sendable {
    case pending
    case applied
  }

  let projectId: String
  let batchId: String
  let createdAt: Date?
  let addedCount: Int
  let modifiedCount: Int
  let deletedCount: Int
  let state: State
  let dir: URL

  var id: String { "\(projectId)::\(batchId)" }

  var changeCount: Int {
    addedCount + modifiedCount + deletedCount
  }

  var createdAtDisplay: String {
    guard let createdAt else { return batchId }
    return DateFormatter.localizedString(from: createdAt, dateStyle: .short, timeStyle: .short)
  }
}

