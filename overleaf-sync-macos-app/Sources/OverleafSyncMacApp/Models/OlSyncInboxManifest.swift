import Foundation

struct OlSyncInboxManifest: Codable, Hashable {
  struct Changes: Codable, Hashable {
    struct ModifiedEntry: Codable, Hashable {
      let path: String
      let localHash: String
      let remoteHash: String
    }

    let added: [String]
    let modified: [ModifiedEntry]
    let deleted: [String]
  }

  let version: Int
  let baseUrl: String
  let projectId: String
  let batchId: String
  let localDir: String
  let inboxDir: String
  let createdAt: String
  let changes: Changes
}

