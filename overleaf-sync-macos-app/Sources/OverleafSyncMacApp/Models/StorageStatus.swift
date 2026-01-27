import Foundation

struct StorageStatus: Hashable, Sendable {
  struct InboxProject: Hashable, Identifiable, Sendable {
    let projectId: String
    let batchCount: Int
    let keepLast: Int

    var id: String { projectId }
    var overLimitCount: Int { max(0, batchCount - keepLast) }
  }

  struct SnapshotProject: Hashable, Identifiable, Sendable {
    let projectId: String
    let pinnedCount: Int
    let autoCount: Int
    let keepAuto: Int

    var id: String { projectId }
    var overLimitAutoCount: Int { max(0, autoCount - keepAuto) }
  }

  let keepLast: Int
  let inboxProjects: [InboxProject]
  let autoSnapshotKeepLast: Int
  let snapshotProjects: [SnapshotProject]

  var inboxProjectCount: Int { inboxProjects.count }
  var inboxBatchCount: Int { inboxProjects.reduce(0) { $0 + $1.batchCount } }
  var inboxOverLimitProjects: Int { inboxProjects.filter { $0.overLimitCount > 0 }.count }
  var inboxOverLimitBatches: Int { inboxProjects.reduce(0) { $0 + $1.overLimitCount } }

  var snapshotProjectCount: Int { snapshotProjects.count }
  var snapshotPinnedCount: Int { snapshotProjects.reduce(0) { $0 + $1.pinnedCount } }
  var snapshotAutoCount: Int { snapshotProjects.reduce(0) { $0 + $1.autoCount } }
  var snapshotAutoOverLimitProjects: Int { snapshotProjects.filter { $0.overLimitAutoCount > 0 }.count }
  var snapshotAutoOverLimitCount: Int { snapshotProjects.reduce(0) { $0 + $1.overLimitAutoCount } }

  static let empty = StorageStatus(
    keepLast: AppConstants.inboxKeepLastPerProject,
    inboxProjects: [],
    autoSnapshotKeepLast: AppConstants.autoSnapshotKeepLastPerProject,
    snapshotProjects: []
  )
}

struct InboxCleanupPrompt: Hashable, Sendable {
  let keepLast: Int
  let candidatePaths: [String]

  var candidateCount: Int { candidatePaths.count }
}

struct LocalSnapshotsCleanupPrompt: Hashable, Sendable {
  let keepLastAuto: Int
  let candidatePaths: [String]

  var candidateCount: Int { candidatePaths.count }
}
