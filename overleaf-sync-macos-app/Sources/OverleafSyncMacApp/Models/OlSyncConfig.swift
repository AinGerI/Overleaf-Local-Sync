import Foundation

struct OlSyncConfig: Codable, Hashable {
  let baseUrl: String?
  let projectId: String?
  let rootFolderId: String?
  let mongoContainer: String?
  let container: String?
  let linkedAt: String?
  let createdAt: String?
  let pulledAt: String?
}

