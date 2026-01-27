import Foundation

struct LocalSnapshotManifest: Codable, Hashable, Sendable {
  let version: Int
  let createdAt: String
  let projectId: String
  let baseUrl: String
  let localDir: String
  let snapshotDir: String
  let note: String?
}
