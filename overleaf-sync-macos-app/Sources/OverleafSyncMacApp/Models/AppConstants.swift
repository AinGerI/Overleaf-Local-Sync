enum AppConstants {
  static let inboxKeepLastPerProject = 20
  static let autoSnapshotKeepLastPerProject = 5

  static let defaultRemoteFetchIntervalMinutes = 30

  static let inboxManifestFileName = ".ol-sync.inbox.json"
  static let inboxAppliedMarkerFileName = ".ol-sync.applied"
  static let snapshotManifestFileName = ".ol-sync.snapshot.json"
  static let snapshotPinnedMarkerFileName = ".keep"
}
