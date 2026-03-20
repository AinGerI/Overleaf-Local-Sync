import Foundation

struct OlSyncClient {
  let workspaceRoot: URL
  let olSyncPath: URL

  init(workspaceRoot: URL) throws {
    self.workspaceRoot = workspaceRoot
    self.olSyncPath = workspaceRoot.appendingPathComponent("overleaf-sync/ol-sync.mjs")

    if !FileManager.default.fileExists(atPath: olSyncPath.path) {
      throw AppError.missingOlSyncScript(olSyncPath)
    }
  }

  func projects(baseURL: String, email: String? = nil, password: String? = nil) async throws -> [Project] {
    let result = try await run(
      args: ["projects", "--base-url", baseURL, "--json"],
      email: email,
      password: password
    )
    return try Self.decodeJSONPayload([Project].self, from: result, command: "projects --json")
  }

  func link(baseURL: String, projectId: String, dir: URL, email: String? = nil, password: String? = nil) async throws {
    try await link(baseURL: baseURL, projectId: projectId, dir: dir, force: false, email: email, password: password)
  }

  func link(
    baseURL: String,
    projectId: String,
    dir: URL,
    force: Bool,
    email: String? = nil,
    password: String? = nil
  ) async throws {
    var args = ["link", "--base-url", baseURL, "--project-id", projectId, "--dir", dir.path]
    if force { args.append("--force") }
    _ = try await run(
      args: args,
      email: email,
      password: password
    )
  }

  func pull(baseURL: String, projectId: String, dir: URL, email: String? = nil, password: String? = nil) async throws {
    _ = try await run(
      args: ["pull", "--base-url", baseURL, "--project-id", projectId, "--dir", dir.path],
      email: email,
      password: password
    )
  }

  struct CreateResult {
    let projectId: String
    let configPath: String
  }

  func create(
    baseURL: String,
    dir: URL,
    name: String,
    force: Bool = false,
    email: String? = nil,
    password: String? = nil
  ) async throws -> CreateResult {
    var args = ["create", "--base-url", baseURL, "--dir", dir.path, "--name", name]
    if force { args.append("--force") }
    let result = try await run(
      args: args,
      email: email,
      password: password
    )
    // CLI prints either:
    //   "Created <id>\nWrote <path>\n"
    // or legacy variants like:
    //   "Created project: <id>\nWrote config: <path>\n"
    // Keep parsing tolerant.
    let out = result.stdout + "\n" + result.stderr
    let lines = out.split(separator: "\n").map { String($0) }

    func parseCreatedId(from line: String) -> String? {
      if line.contains("Created project:") {
        return line.split(separator: ":").last.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      }
      if line.hasPrefix("Created ") {
        return String(line.dropFirst("Created ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
      }
      return nil
    }

    let projectId = lines.compactMap(parseCreatedId).first
    let cfgPath =
      lines.first(where: { $0.contains("Wrote config:") })?
        .split(separator: ":")
        .dropFirst()
        .joined(separator: ":")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      ?? lines.first(where: { $0.hasPrefix("Wrote ") })
        .map { String($0.dropFirst("Wrote ".count)).trimmingCharacters(in: .whitespacesAndNewlines) }

    guard let projectId, !projectId.isEmpty else {
      throw NSError(domain: "OlSyncClient", code: 2, userInfo: [NSLocalizedDescriptionKey: out])
    }
    return CreateResult(projectId: projectId, configPath: cfgPath ?? "")
  }

  func push(
    baseURL: String,
    dir: URL,
    concurrency: Int,
    dryRun: Bool,
    email: String? = nil,
    password: String? = nil
  ) async throws {
    var args = ["push", "--base-url", baseURL, "--dir", dir.path, "--concurrency", "\(concurrency)"]
    if dryRun { args.append("--dry-run") }
    _ = try await run(args: args, email: email, password: password)
  }

  func fetch(
    baseURL: String,
    dir: URL,
    skipEmpty: Bool = false,
    email: String? = nil,
    password: String? = nil
  ) async throws -> OlSyncInboxManifest {
    var args = ["fetch", "--base-url", baseURL, "--dir", dir.path, "--json"]
    if skipEmpty { args.append("--skip-empty") }
    let result = try await run(
      args: args,
      email: email,
      password: password
    )
    return try Self.decodeJSONPayload(OlSyncInboxManifest.self, from: result, command: "fetch --json")
  }

  func apply(
    baseURL: String,
    dir: URL,
    batchId: String?,
    email: String? = nil,
    password: String? = nil
  ) async throws -> CommandResult {
    var args = ["apply", "--base-url", baseURL, "--dir", dir.path]
    if let batchId, !batchId.isEmpty {
      args += ["--batch", batchId]
    }
    return try await run(args: args, email: email, password: password)
  }

  // MARK: - Project management

  func projectArchive(baseURL: String, projectId: String, email: String? = nil, password: String? = nil) async throws {
    _ = try await run(
      args: ["project-archive", "--base-url", baseURL, "--project-id", projectId],
      email: email,
      password: password
    )
  }

  func projectUnarchive(baseURL: String, projectId: String, email: String? = nil, password: String? = nil) async throws {
    _ = try await run(
      args: ["project-unarchive", "--base-url", baseURL, "--project-id", projectId],
      email: email,
      password: password
    )
  }

  func projectTrash(baseURL: String, projectId: String, email: String? = nil, password: String? = nil) async throws {
    _ = try await run(
      args: ["project-trash", "--base-url", baseURL, "--project-id", projectId],
      email: email,
      password: password
    )
  }

  func projectUntrash(baseURL: String, projectId: String, email: String? = nil, password: String? = nil) async throws {
    _ = try await run(
      args: ["project-untrash", "--base-url", baseURL, "--project-id", projectId],
      email: email,
      password: password
    )
  }

  func projectDeletePermanently(
    baseURL: String,
    projectId: String,
    email: String? = nil,
    password: String? = nil
  ) async throws {
    _ = try await run(
      args: ["project-delete", "--base-url", baseURL, "--project-id", projectId],
      email: email,
      password: password
    )
  }

  // MARK: - Process

  struct CommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
  }

  static func decodeJSONPayload<T: Decodable>(
    _ type: T.Type,
    from result: CommandResult,
    command: String
  ) throws -> T {
    let decoder = JSONDecoder()
    let normalizedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

    do {
      return try decoder.decode(T.self, from: Data(normalizedStdout.utf8))
    } catch {
      for candidate in fallbackJSONPayloads(from: result.stdout) {
        do {
          return try decoder.decode(T.self, from: Data(candidate.utf8))
        } catch {
          continue
        }
      }
      throw jsonDecodeError(command: command, stdout: result.stdout, stderr: result.stderr, underlying: error)
    }
  }

  func run(args: [String], email: String?, password: String?) async throws -> CommandResult {
    let env = credentialsEnv(email: email, password: password)
    return try await ProcessRunner.run(
      executable: "/usr/bin/env",
      arguments: ["node", olSyncPath.path] + args,
      currentDirectory: workspaceRoot,
      environment: env
    )
  }

  private func credentialsEnv(email: String?, password: String?) -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    if let email, !email.isEmpty { env["OVERLEAF_SYNC_EMAIL"] = email }
    if let password, !password.isEmpty { env["OVERLEAF_SYNC_PASSWORD"] = password }
    return env
  }

  private static func fallbackJSONPayloads(from stdout: String) -> [String] {
    let lines = stdout
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
    let original = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    var candidates: [String] = []

    for index in lines.indices {
      let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { continue }
      let candidate = lines[index...]
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !candidate.isEmpty, candidate != original, !candidates.contains(candidate) else { continue }
      candidates.append(candidate)
    }

    return candidates
  }

  private static func jsonDecodeError(
    command: String,
    stdout: String,
    stderr: String,
    underlying: Error
  ) -> NSError {
    var lines = ["Failed to decode JSON output from \(command)."]
    let stdoutPreview = outputPreview(stdout)
    let stderrPreview = outputPreview(stderr)
    if !stdoutPreview.isEmpty {
      lines.append("stdout: \(stdoutPreview)")
    }
    if !stderrPreview.isEmpty {
      lines.append("stderr: \(stderrPreview)")
    }
    lines.append("underlying: \((underlying as NSError).localizedDescription)")
    return NSError(
      domain: "OlSyncClient",
      code: 3,
      userInfo: [NSLocalizedDescriptionKey: lines.joined(separator: "\n")]
    )
  }

  private static func outputPreview(_ text: String, limit: Int = 240) -> String {
    let normalized = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\n", with: " \\n ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return "" }
    guard normalized.count > limit else { return normalized }
    return String(normalized.prefix(limit)) + "..."
  }
}
