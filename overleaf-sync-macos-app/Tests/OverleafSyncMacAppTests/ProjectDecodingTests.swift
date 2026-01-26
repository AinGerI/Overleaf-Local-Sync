import Foundation
import Testing

@testable import OverleafSyncMacApp

@Test
func projectDecoding() throws {
  let raw = """
  [
    {
      "id": "123",
      "name": "Demo",
      "accessLevel": "owner",
      "archived": false,
      "trashed": false,
      "lastUpdated": "2026-01-26T05:36:13.585Z",
      "lastUpdatedBy": "user@example.com"
    }
  ]
  """
  let decoded = try JSONDecoder().decode([Project].self, from: Data(raw.utf8))
  #expect(decoded.count == 1)
  #expect(decoded[0].id == "123")
  #expect(decoded[0].lastUpdatedDate != nil)
}

