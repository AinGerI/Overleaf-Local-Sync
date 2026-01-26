import Foundation

enum ProcessRunner {
  private static let preferredPathEntries = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
  ]

  final class DataBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
      lock.lock()
      data.append(chunk)
      lock.unlock()
    }

    func snapshot() -> Data {
      lock.lock()
      defer { lock.unlock() }
      return data
    }
  }

  static func run(
    executable: String,
    arguments: [String],
    currentDirectory: URL,
    environment: [String: String]
  ) async throws -> OlSyncClient.CommandResult {
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    let stdoutBuffer = DataBuffer()
    let stderrBuffer = DataBuffer()

    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
      let chunk = handle.availableData
      if !chunk.isEmpty { stdoutBuffer.append(chunk) }
    }
    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
      let chunk = handle.availableData
      if !chunk.isEmpty { stderrBuffer.append(chunk) }
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: executable)
    proc.arguments = arguments
    proc.currentDirectoryURL = currentDirectory
    proc.environment = mergedEnvironment(environment)
    proc.standardOutput = stdoutPipe
    proc.standardError = stderrPipe

    return try await withCheckedThrowingContinuation { cont in
      proc.terminationHandler = { process in
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let exitCode = process.terminationStatus
        let stdout = String(data: stdoutBuffer.snapshot(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrBuffer.snapshot(), encoding: .utf8) ?? ""
        let result = OlSyncClient.CommandResult(exitCode: exitCode, stdout: stdout, stderr: stderr)

        if exitCode == 0 {
          cont.resume(returning: result)
        } else {
          let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
          cont.resume(throwing: NSError(
            domain: "ProcessRunner",
            code: Int(exitCode),
            userInfo: [
              NSLocalizedDescriptionKey: combined.isEmpty
                ? "Command failed with exit code \(exitCode)"
                : combined,
            ]
          ))
        }
      }

      do {
        try proc.run()
      } catch {
        cont.resume(throwing: error)
      }
    }
  }

  private static func mergedEnvironment(_ base: [String: String]) -> [String: String] {
    var env = base
    let existing = env["PATH"]
    var parts: [String] = []
    func add(_ p: String) {
      guard !p.isEmpty, !parts.contains(p) else { return }
      parts.append(p)
    }

    for p in preferredPathEntries { add(p) }
    if let existing {
      for p in existing.split(separator: ":").map(String.init) { add(p) }
    }

    env["PATH"] = parts.joined(separator: ":")
    return env
  }
}
