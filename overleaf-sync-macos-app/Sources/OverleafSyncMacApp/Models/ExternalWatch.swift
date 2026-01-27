import Foundation

struct ExternalWatch: Identifiable, Hashable {
  let dir: URL
  let pids: [Int32]

  var id: String { dir.path }
  var title: String { dir.lastPathComponent }
}

enum WatchSelection: Hashable, Identifiable {
  case `internal`(UUID)
  case external(String)

  var id: String {
    switch self {
    case let .internal(id): "internal:\(id.uuidString)"
    case let .external(key): "external:\(key)"
    }
  }
}

