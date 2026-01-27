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
    let data = Data(result.stdout.utf8)
    return try JSONDecoder().decode([Project].self, from: data)
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
    let data = Data(result.stdout.utf8)
    return try JSONDecoder().decode(OlSyncInboxManifest.self, from: data)
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

  // MARK: - Process

  struct CommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
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
}
