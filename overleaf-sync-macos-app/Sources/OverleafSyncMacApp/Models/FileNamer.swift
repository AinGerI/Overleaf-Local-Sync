import Foundation

enum FileNamer {
  static func safeDirectoryName(_ input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "OverleafProject" }
    return trimmed
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
  }

  static func uniqueDirectory(parent: URL, preferredName: String) throws -> URL {
    let fm = FileManager.default
    var candidate = parent.appendingPathComponent(preferredName)
    if !fm.fileExists(atPath: candidate.path) { return candidate }

    for i in 2...999 {
      candidate = parent.appendingPathComponent("\(preferredName) (\(i))")
      if !fm.fileExists(atPath: candidate.path) { return candidate }
    }
    throw AppError.cannotCreateUniqueDirectory(preferredName)
  }
}

