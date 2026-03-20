import Foundation
import Testing

@testable import OverleafSyncMacApp

@Test
func decodeJSONPayloadAcceptsPureProjectJSON() throws {
  let result = OlSyncClient.CommandResult(
    exitCode: 0,
    stdout: """
    [{"id":"123","name":"Demo","accessLevel":"owner","archived":false,"trashed":false,"lastUpdated":"2026-01-26T05:36:13.585Z","lastUpdatedBy":"user@example.com"}]
    """,
    stderr: ""
  )

  let projects = try OlSyncClient.decodeJSONPayload(
    [Project].self,
    from: result,
    command: "projects --json"
  )

  #expect(projects.count == 1)
  #expect(projects[0].id == "123")
}

@Test
func decodeJSONPayloadRecoversFromPrefixedNotice() throws {
  let result = OlSyncClient.CommandResult(
    exitCode: 0,
    stdout: """
    Session cached at /tmp/session.json
    [{"id":"123","name":"Demo","accessLevel":"owner","archived":false,"trashed":false,"lastUpdated":"2026-01-26T05:36:13.585Z","lastUpdatedBy":"user@example.com"}]
    """,
    stderr: ""
  )

  let projects = try OlSyncClient.decodeJSONPayload(
    [Project].self,
    from: result,
    command: "projects --json"
  )

  #expect(projects.count == 1)
  #expect(projects[0].name == "Demo")
}

@Test
func decodeJSONPayloadRecoversManifestFromPrefixedNotice() throws {
  let result = OlSyncClient.CommandResult(
    exitCode: 0,
    stdout: """
    Session cached at /tmp/session.json
    {"version":1,"baseUrl":"http://localhost","projectId":"abc","batchId":"2026-03-16T10-00-00Z","localDir":"/tmp/project","inboxDir":"/tmp/inbox","createdAt":"2026-03-16T10:00:00Z","changes":{"added":["main.tex"],"modified":[],"deleted":[]},"saved":true}
    """,
    stderr: ""
  )

  let manifest = try OlSyncClient.decodeJSONPayload(
    OlSyncInboxManifest.self,
    from: result,
    command: "fetch --json"
  )

  #expect(manifest.projectId == "abc")
  #expect(manifest.changes.added == ["main.tex"])
}

@Test
func decodeJSONPayloadIncludesPreviewOnFailure() {
  let result = OlSyncClient.CommandResult(
    exitCode: 0,
    stdout: "not-json",
    stderr: "Session cached at /tmp/session.json"
  )

  do {
    let _: [Project] = try OlSyncClient.decodeJSONPayload(
      [Project].self,
      from: result,
      command: "projects --json"
    )
    Issue.record("Expected JSON decoding to fail")
  } catch {
    let message = (error as NSError).localizedDescription
    #expect(message.contains("Failed to decode JSON output from projects --json."))
    #expect(message.contains("stdout: not-json"))
    #expect(message.contains("stderr: Session cached at /tmp/session.json"))
  }
}
