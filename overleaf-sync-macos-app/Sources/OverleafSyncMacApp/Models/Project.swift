import Foundation

struct Project: Codable, Identifiable, Hashable {
  let id: String
  let name: String
  let accessLevel: String
  let archived: Bool
  let trashed: Bool
  let lastUpdated: String?
  let lastUpdatedBy: String?

  var lastUpdatedDate: Date? {
    guard let lastUpdated else { return nil }
    return DateParsing.parseISO8601WithFractionalSeconds(lastUpdated)
  }

  var lastUpdatedDisplay: String {
    guard let date = lastUpdatedDate else { return lastUpdated ?? "" }
    return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
  }
}
