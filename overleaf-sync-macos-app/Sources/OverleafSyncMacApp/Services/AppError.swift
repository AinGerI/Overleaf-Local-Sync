import Foundation

enum AppError: LocalizedError {
  case missingWorkspaceRoot
  case missingOlSyncScript(URL)
  case cannotCreateUniqueDirectory(String)

  var errorDescription: String? {
    switch self {
    case .missingWorkspaceRoot:
      return "Workspace root is not set. Choose the repository root first."
    case .missingOlSyncScript(let url):
      return "Cannot find ol-sync.mjs at: \(url.path)"
    case .cannotCreateUniqueDirectory(let name):
      return "Cannot create a unique directory under the selected parent: \(name)"
    }
  }
}

