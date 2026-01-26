import Foundation

enum DateParsing {
  static func parseISO8601WithFractionalSeconds(_ value: String) -> Date? {
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fmt.date(from: value)
  }
}
