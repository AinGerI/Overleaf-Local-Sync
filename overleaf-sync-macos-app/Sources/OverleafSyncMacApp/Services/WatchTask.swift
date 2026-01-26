import Foundation

@MainActor
final class WatchTask: ObservableObject, Identifiable {
  let id = UUID()
  let title: String
  let workspaceRoot: URL
  let baseURL: String
  let dir: URL

  @Published var isRunning: Bool = false
  @Published var output: String = ""

  var onEvent: ((String) -> Void)?
  var onExit: (() -> Void)?

  private var process: Process?
  private var stdoutPipe: Pipe?
  private var stderrPipe: Pipe?

  private init(title: String, workspaceRoot: URL, baseURL: String, dir: URL) {
    self.title = title
    self.workspaceRoot = workspaceRoot
    self.baseURL = baseURL
    self.dir = dir
  }

  static func start(
    title: String,
    workspaceRoot: URL,
    baseURL: String,
    dir: URL,
    credentials: Credentials?
  ) throws -> WatchTask {
    let task = WatchTask(title: title, workspaceRoot: workspaceRoot, baseURL: baseURL, dir: dir)
    try task.start(credentials: credentials)
    return task
  }

  func stop() {
    process?.terminate()
  }

  private func start(credentials: Credentials?) throws {
    let olSyncPath = workspaceRoot.appendingPathComponent("overleaf-sync/ol-sync.mjs")
    if !FileManager.default.fileExists(atPath: olSyncPath.path) {
      throw AppError.missingOlSyncScript(olSyncPath)
    }

    let out = Pipe()
    let err = Pipe()
    stdoutPipe = out
    stderrPipe = err

    out.fileHandleForReading.readabilityHandler = { [weak self] handle in
      guard let self else { return }
      let data = handle.availableData
      if data.isEmpty { return }
      let text = String(data: data, encoding: .utf8) ?? ""
      Task { @MainActor in
        self.appendOutput(text)
        self.onEvent?(text.trimmingCharacters(in: .newlines))
      }
    }

    err.fileHandleForReading.readabilityHandler = { [weak self] handle in
      guard let self else { return }
      let data = handle.availableData
      if data.isEmpty { return }
      let text = String(data: data, encoding: .utf8) ?? ""
      Task { @MainActor in
        self.appendOutput(text)
      }
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = [
      "node",
      olSyncPath.path,
      "watch",
      "--base-url",
      baseURL,
      "--dir",
      dir.path,
    ]
    proc.currentDirectoryURL = workspaceRoot
    proc.standardOutput = out
    proc.standardError = err

    var env = ProcessInfo.processInfo.environment
    let preferredPathEntries = [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "/usr/bin",
      "/bin",
      "/usr/sbin",
      "/sbin",
    ]
    let existingPath = env["PATH"]
    var parts: [String] = []
    func add(_ p: String) {
      guard !p.isEmpty, !parts.contains(p) else { return }
      parts.append(p)
    }
    for p in preferredPathEntries { add(p) }
    if let existingPath {
      for p in existingPath.split(separator: ":").map(String.init) { add(p) }
    }
    env["PATH"] = parts.joined(separator: ":")
    if let credentials {
      env["OVERLEAF_SYNC_EMAIL"] = credentials.email
      env["OVERLEAF_SYNC_PASSWORD"] = credentials.password
    }
    proc.environment = env

    proc.terminationHandler = { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        self.isRunning = false
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        self.onExit?()
      }
    }

    try proc.run()
    process = proc
    isRunning = true
  }

  private func appendOutput(_ chunk: String) {
    if output.isEmpty {
      output = chunk
    } else {
      output += chunk
    }
    if output.count > 250_000 {
      output = String(output.suffix(180_000))
    }
  }
}
