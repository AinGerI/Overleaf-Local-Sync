import AppKit
import Darwin
import Foundation

@MainActor
final class AppModel: ObservableObject {
  static let configFileName = ".ol-sync.json"
  private var externalWatchPollTask: Task<Void, Never>?
  private var autoRemoteFetchTask: Task<Void, Never>?

  @Published var workspaceRoot: URL? {
    didSet {
      Preferences.setPath(workspaceRoot, forKey: Preferences.Key.workspaceRoot)
      refreshLocalIndex()
      Task { await refreshExternalWatches() }
      Task { await refreshStorageStatus() }
      Task { await refreshHistoryIndexes() }
    }
  }

  @Published var baseURL: String {
    didSet {
      Preferences.setString(baseURL, forKey: Preferences.Key.baseURL)
      Task { await refreshHistoryIndexes() }
      startAutoRemoteFetchLoop()
    }
  }

  @Published var email: String {
    didSet { Preferences.setString(email, forKey: Preferences.Key.email) }
  }

  @Published var localFolder: URL? {
    didSet {
      Preferences.setPath(localFolder, forKey: Preferences.Key.localFolder)
      reloadLocalFolderConfig()
    }
  }

  @Published var pullParentFolder: URL? {
    didSet { Preferences.setPath(pullParentFolder, forKey: Preferences.Key.pullParentFolder) }
  }

  @Published var projects: [Project] = []
  @Published var selectedProjectId: Project.ID? {
    didSet { Task { await refreshSelectedProjectHistory() } }
  }

  @Published var autoRemoteFetchEnabled: Bool {
    didSet {
      Preferences.setBool(autoRemoteFetchEnabled, forKey: Preferences.Key.autoRemoteFetchEnabled)
      startAutoRemoteFetchLoop()
    }
  }

  @Published var autoRemoteFetchIntervalMinutes: Int {
    didSet {
      Preferences.setInt(autoRemoteFetchIntervalMinutes, forKey: Preferences.Key.autoRemoteFetchIntervalMinutes)
      startAutoRemoteFetchLoop()
    }
  }

  @Published var watches: [WatchTask] = []
  @Published var externalWatches: [ExternalWatch] = []
  @Published var selectedWatchSelection: WatchSelection?

  @Published var logText: String = ""
  @Published var alert: AlertItem?

  @Published var showLoginSheet: Bool = false
  @Published var password: String = ""

  @Published var pushConcurrency: Int = 4

  @Published var localFolderConfig: OlSyncConfig?
  @Published var overwritePrompt: OverwritePrompt?
  @Published var projectsRoot: URL?
  @Published var linkedFoldersByProjectId: [String: URL] = [:]
  @Published var remoteManifest: OlSyncInboxManifest?
  @Published var remoteApplyPrompt: RemoteApplyPrompt?
  @Published var rootConfigPrompt: RootConfigPrompt?
  @Published var newFolderPrompt: NewFolderPrompt?
  @Published var storageStatus: StorageStatus = .empty
  @Published var inboxCleanupPrompt: InboxCleanupPrompt?
  @Published var localSnapshotsCleanupPrompt: LocalSnapshotsCleanupPrompt?
  @Published var remoteInboxBatchesByProjectId: [String: [RemoteInboxBatch]] = [:]
  @Published var localSnapshotsByProjectId: [String: [LocalSnapshotItem]] = [:]
  @Published var selectedProjectInboxBatches: [RemoteInboxBatch] = []
  @Published var selectedProjectSnapshots: [LocalSnapshotItem] = []
  @Published var snapshotRestorePrompt: SnapshotRestorePrompt?

  deinit {
    externalWatchPollTask?.cancel()
    autoRemoteFetchTask?.cancel()
  }

  init() {
    self.workspaceRoot = Preferences.getPath(forKey: Preferences.Key.workspaceRoot)
    self.baseURL = Preferences.getString(forKey: Preferences.Key.baseURL) ?? "http://localhost"
    self.email = Preferences.getString(forKey: Preferences.Key.email) ?? ""
    self.localFolder = Preferences.getPath(forKey: Preferences.Key.localFolder)
    self.pullParentFolder = Preferences.getPath(forKey: Preferences.Key.pullParentFolder)
    self.autoRemoteFetchEnabled =
      Preferences.getBool(forKey: Preferences.Key.autoRemoteFetchEnabled) ?? true
    self.autoRemoteFetchIntervalMinutes =
      max(1, Preferences.getInt(forKey: Preferences.Key.autoRemoteFetchIntervalMinutes) ?? AppConstants.defaultRemoteFetchIntervalMinutes)

    applyLaunchArguments()
    reloadLocalFolderConfig()
    refreshLocalIndex()
    startExternalWatchPolling()
    startAutoRemoteFetchLoop()
    Task { await refreshStorageStatus() }
    Task { await refreshHistoryIndexes() }
  }

  var selectedProject: Project? {
    guard let selectedProjectId else { return nil }
    return projects.first(where: { $0.id == selectedProjectId })
  }

  var selectedWatch: WatchTask? {
    guard let selectedWatchSelection else { return nil }
    guard case let .internal(id) = selectedWatchSelection else { return nil }
    return watches.first(where: { $0.id == id })
  }

  var selectedExternalWatch: ExternalWatch? {
    guard let selectedWatchSelection else { return nil }
    guard case let .external(key) = selectedWatchSelection else { return nil }
    return externalWatches.first(where: { $0.id == key })
  }

  func pickWorkspaceRoot() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    panel.message = "Choose the repository root that contains overleaf-sync/ol-sync.mjs"
    panel.directoryURL = workspaceRoot

    if panel.runModal() == .OK {
      workspaceRoot = panel.url
    }
  }

  func pickLocalFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    panel.message = "Choose a local project folder to link/push/watch"
    panel.directoryURL = localFolder ?? projectsRoot ?? pullParentFolder ?? workspaceRoot

    if panel.runModal() == .OK {
      localFolder = panel.url
    }
  }

  func pickPullParentFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    panel.message = "Choose a parent folder where the project will be downloaded"
    panel.directoryURL = pullParentFolder ?? projectsRoot ?? workspaceRoot

    if panel.runModal() == .OK {
      pullParentFolder = panel.url
    }
  }

  func refreshProjects() async {
    if workspaceRoot == nil {
      pickWorkspaceRoot()
    }
    if workspaceRoot == nil {
      alert = AlertItem(
        title: "Missing workspace",
        message: "Choose the repository root first (the folder that contains overleaf-sync/ol-sync.mjs)."
      )
      return
    }
    do {
      let client = try makeClient()
      appendLog("→ projects --json")
      let fetched = try await client.projects(baseURL: baseURL)
      projects = fetched.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
      refreshLocalIndex()
      await refreshStorageStatus()
    } catch {
      handleCommandError(error)
    }
  }

  func login() async {
    do {
      let client = try makeClient()
      appendLog("→ projects --json (login)")
      _ = try await client.projects(
        baseURL: baseURL,
        email: email.isEmpty ? nil : email,
        password: password.isEmpty ? nil : password
      )
      password = ""
      showLoginSheet = false
      await refreshProjects()
    } catch {
      handleCommandError(error)
    }
  }

  func linkSelectedProject() async {
    guard let project = selectedProject else {
      alert = AlertItem(title: "Missing project", message: "Select a project first.")
      return
    }
    guard let dir = localFolder else {
      alert = AlertItem(title: "Missing folder", message: "Choose a local folder first.")
      return
    }

    if let cfg = readConfig(in: dir) {
      if cfg.projectId == project.id {
        alert = AlertItem(
          title: "Already linked",
          message: "This folder already has \(Self.configFileName) for the selected project. Use Push/Watch."
        )
        return
      }
      overwritePrompt = OverwritePrompt(
        kind: .link,
        dir: dir,
        existingProjectId: cfg.projectId,
        targetProjectId: project.id
      )
      return
    }

    do {
      let client = try makeClient()
      appendLog("→ link \(project.id) \(dir.path)")
      try await client.link(
        baseURL: baseURL,
        projectId: project.id,
        dir: dir,
        email: email.isEmpty ? nil : email,
        password: password.isEmpty ? nil : password
      )
      reloadLocalFolderConfig()
      refreshLocalIndex()
    } catch {
      handleCommandError(error)
    }
  }

  func confirmOverwriteLink(_ prompt: OverwritePrompt) async {
    guard prompt.kind == .link else { return }
    guard let targetProjectId = prompt.targetProjectId else { return }
    do {
      _ = try backupConfigIfExists(in: prompt.dir)

      let client = try makeClient()
      appendLog("→ link --force \(targetProjectId) \(prompt.dir.path)")
      try await client.link(
        baseURL: baseURL,
        projectId: targetProjectId,
        dir: prompt.dir,
        force: true,
        email: email.isEmpty ? nil : email,
        password: password.isEmpty ? nil : password
      )
      localFolder = prompt.dir
      reloadLocalFolderConfig()
      refreshLocalIndex()
      await refreshStorageStatus()
    } catch {
      handleCommandError(error)
    }
  }

  func pullSelectedProject() async {
    guard let project = selectedProject else {
      alert = AlertItem(title: "Missing project", message: "Select a project first.")
      return
    }
    guard let parent = pullParentFolder else {
      pickPullParentFolder()
      guard let parent = pullParentFolder else { return }
      await pullSelectedProjectInto(parent: parent, project: project)
      return
    }
    await pullSelectedProjectInto(parent: parent, project: project)
  }

  private func pullSelectedProjectInto(parent: URL, project: Project) async {
    do {
      let client = try makeClient()
      let target = try FileNamer.uniqueDirectory(
        parent: parent,
        preferredName: FileNamer.safeDirectoryName(project.name)
      )
      try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
      localFolder = target

      appendLog("→ pull \(project.id) \(target.path)")
      try await client.pull(
        baseURL: baseURL,
        projectId: project.id,
        dir: target,
        email: email.isEmpty ? nil : email,
        password: password.isEmpty ? nil : password
      )
      refreshLocalIndex()
    } catch {
      handleCommandError(error)
    }
  }

  func pushLocalFolder(dryRun: Bool) async {
    guard let dir = localFolder else {
      alert = AlertItem(title: "Missing folder", message: "Choose a local folder first.")
      return
    }

    do {
      let client = try makeClient()
      appendLog("→ push \(dir.path) (concurrency=\(pushConcurrency), dryRun=\(dryRun))")
      try await client.push(
        baseURL: baseURL,
        dir: dir,
        concurrency: pushConcurrency,
        dryRun: dryRun,
        email: email.isEmpty ? nil : email,
        password: password.isEmpty ? nil : password
      )
    } catch {
      handleCommandError(error)
    }
  }

  func startWatchForLocalFolder() {
    guard let dir = localFolder else {
      alert = AlertItem(title: "Missing folder", message: "Choose a local folder first.")
      return
    }
    do {
      let didStart = try startWatch(for: dir)
      if !didStart {
        alert = AlertItem(title: "Already running", message: "A watch is already running for this folder.")
      }
    } catch {
      handleCommandError(error)
    }
  }

  func startWatchAllLinkedProjects() {
    let dirs = linkedFoldersByProjectId.values.sorted { $0.path < $1.path }
    if dirs.isEmpty {
      alert = AlertItem(
        title: "No linked folders",
        message: "No linked local folders found under overleaf-projects. Pull or Link a project first."
      )
      return
    }

    var started = 0
    var already = 0
    var failed = 0
    for dir in dirs {
      do {
        let didStart = try startWatch(for: dir)
        if didStart { started += 1 } else { already += 1 }
      } catch {
        failed += 1
        appendLog("error: failed to start watch for \(dir.path): \((error as NSError).localizedDescription)")
      }
    }

    alert = AlertItem(
      title: "Watch all linked",
      message: "started=\(started), alreadyRunning=\(already), failed=\(failed)"
    )
  }

  func stopSelectedWatch() {
    if let watch = selectedWatch {
      watch.stop()
      return
    }
    if let watch = selectedExternalWatch {
      stopExternalWatch(watch)
    }
  }

  func stopExternalWatch(_ watch: ExternalWatch) {
    var stopped = 0
    for pid in watch.pids {
      if kill(pid, SIGTERM) == 0 { stopped += 1 }
    }
    appendLog("stop external watch: \(watch.dir.path) pids=\(watch.pids.count) stopped=\(stopped)")
    Task {
      try? await Task.sleep(nanoseconds: 350_000_000)
      await refreshExternalWatches()
    }
  }

  func dedupeExternalWatch(_ watch: ExternalWatch) {
    let sorted = watch.pids.sorted()
    guard sorted.count > 1 else { return }
    guard let keep = sorted.last else { return }

    var stopped = 0
    for pid in sorted where pid != keep {
      if kill(pid, SIGTERM) == 0 { stopped += 1 }
    }
    appendLog("dedupe external watch: \(watch.dir.path) keep=\(keep) stopped=\(stopped)")
    Task {
      try? await Task.sleep(nanoseconds: 350_000_000)
      await refreshExternalWatches()
    }
  }

  func openExternalWatchLogs(_ watch: ExternalWatch) {
    guard let root = workspaceRoot else { return }
    let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
      ?? (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config").path)
    let stateDir = URL(fileURLWithPath: configHome)
      .appendingPathComponent("overleaf-sync")
      .appendingPathComponent("autowatch")

    do {
      let entries = try FileManager.default.contentsOfDirectory(
        at: stateDir,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
      let pidFiles = entries.filter { $0.pathExtension == "pids" }
      for pidFile in pidFiles {
        let raw = (try? String(contentsOf: pidFile, encoding: .utf8)) ?? ""
        if raw.contains(root.path) {
          let logsDir = pidFile.deletingPathExtension().appendingPathExtension("logs")
          if FileManager.default.fileExists(atPath: logsDir.path) {
            NSWorkspace.shared.open(logsDir)
            return
          }
        }
      }
    } catch {
      // ignore
    }
  }

  func createRemoteProjectFromLocalFolder() async {
    guard let dir = localFolder else {
      alert = AlertItem(title: "Missing folder", message: "Choose a local folder first.")
      return
    }

    if let root = projectsRoot, dir == root {
      newFolderPrompt = NewFolderPrompt(parent: root)
      return
    }

    if let cfg = readConfig(in: dir) {
      overwritePrompt = OverwritePrompt(
        kind: .create,
        dir: dir,
        existingProjectId: cfg.projectId,
        targetProjectId: nil
      )
      return
    }

    do {
      let client = try makeClient()
      appendLog("→ create \(dir.path)")
      let created = try await client.create(
        baseURL: baseURL,
        dir: dir,
        name: dir.lastPathComponent,
        email: email.isEmpty ? nil : email,
        password: password.isEmpty ? nil : password
      )
      appendLog("created project: \(created.projectId)")
      reloadLocalFolderConfig()
      refreshLocalIndex()
      await refreshProjects()
    } catch {
      handleCommandError(error)
    }
  }

  func confirmCreateNewFolder(_ prompt: NewFolderPrompt, name: String, startWatchAfterCreate: Bool) async {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      alert = AlertItem(title: "Missing name", message: "Enter a project name.")
      return
    }

    do {
      let preferred = FileNamer.safeDirectoryName(trimmed)
      let target = try FileNamer.uniqueDirectory(parent: prompt.parent, preferredName: preferred)
      try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
      localFolder = target

      let client = try makeClient()
      appendLog("→ create \(target.path)")
      let created = try await client.create(
        baseURL: baseURL,
        dir: target,
        name: trimmed,
        email: email.isEmpty ? nil : email,
        password: password.isEmpty ? nil : password
      )
      appendLog("created project: \(created.projectId)")
      reloadLocalFolderConfig()
      refreshLocalIndex()
      await refreshProjects()

      if startWatchAfterCreate {
        _ = try startWatch(for: target)
      }
    } catch {
      handleCommandError(error)
    }
  }

  func confirmOverwriteCreate(_ prompt: OverwritePrompt) async {
    guard prompt.kind == .create else { return }
    do {
      _ = try backupConfigIfExists(in: prompt.dir)

      let client = try makeClient()
      appendLog("→ create --force \(prompt.dir.path)")
      let created = try await client.create(
        baseURL: baseURL,
        dir: prompt.dir,
        name: prompt.dir.lastPathComponent,
        force: true,
        email: email.isEmpty ? nil : email,
        password: password.isEmpty ? nil : password
      )
      appendLog("created project: \(created.projectId)")
      localFolder = prompt.dir
      reloadLocalFolderConfig()
      refreshLocalIndex()
      await refreshProjects()
    } catch {
      handleCommandError(error)
    }
  }

  // MARK: - Helpers

  private func makeClient() throws -> OlSyncClient {
    let root = try requireWorkspaceRoot()
    return try OlSyncClient(workspaceRoot: root)
  }

  private func requireWorkspaceRoot() throws -> URL {
    guard let root = workspaceRoot else {
      throw AppError.missingWorkspaceRoot
    }
    return root
  }

  private func currentCredentials() -> Credentials? {
    guard !email.isEmpty, !password.isEmpty else { return nil }
    return Credentials(email: email, password: password)
  }

  private func appendLog(_ line: String) {
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let newLine = "[\(ts)] \(line)"
    if logText.isEmpty {
      logText = newLine
    } else {
      logText += "\n" + newLine
    }
    if logText.count > 200_000 {
      logText = String(logText.suffix(150_000))
    }
  }

  private func handleCommandError(_ error: Error) {
    let message = (error as NSError).localizedDescription
    appendLog("error: \(message)")
    if message.contains("Cannot prompt for Overleaf email")
      || message.contains("Cannot prompt for Overleaf password")
    {
      showLoginSheet = true
      return
    }
    alert = AlertItem(title: "Command failed", message: message)
  }

  private func configPath(in dir: URL) -> URL {
    dir.appendingPathComponent(Self.configFileName)
  }

  @discardableResult
  private func backupConfigIfExists(in dir: URL) throws -> URL? {
    let src = configPath(in: dir)
    guard FileManager.default.fileExists(atPath: src.path) else { return nil }
    let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
    let dst = dir.appendingPathComponent("\(Self.configFileName).bak.\(ts)")
    try FileManager.default.moveItem(at: src, to: dst)
    appendLog("moved config backup: \(dst.lastPathComponent)")
    return dst
  }

  private func readConfig(in dir: URL) -> OlSyncConfig? {
    let url = configPath(in: dir)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
      let data = try Data(contentsOf: url)
      return try JSONDecoder().decode(OlSyncConfig.self, from: data)
    } catch {
      return nil
    }
  }

  private func reloadLocalFolderConfig() {
    guard let dir = localFolder else {
      localFolderConfig = nil
      return
    }
    localFolderConfig = readConfig(in: dir)
  }

  private func projectsRootCandidate() -> URL? {
    guard let root = workspaceRoot else { return nil }
    let candidate = root.appendingPathComponent("overleaf-projects")
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir),
          isDir.boolValue
    else { return nil }
    return candidate
  }

  func refreshLocalIndex() {
    guard let root = projectsRootCandidate() else {
      projectsRoot = nil
      linkedFoldersByProjectId = [:]
      return
    }

    do {
      let entries = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
      var map: [String: URL] = [:]
      for dir in entries {
        guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        guard let cfg = readConfig(in: dir), let pid = cfg.projectId, !pid.isEmpty else { continue }
        map[pid] = dir
      }
      projectsRoot = root
      linkedFoldersByProjectId = map
    } catch {
      projectsRoot = root
      linkedFoldersByProjectId = [:]
      appendLog("warn: failed to scan overleaf-projects for links: \((error as NSError).localizedDescription)")
    }
  }

  func refreshExternalWatches() async {
    guard let root = workspaceRoot else {
      externalWatches = []
      return
    }

    let olSyncPath = root.appendingPathComponent("overleaf-sync/ol-sync.mjs").path
    if !FileManager.default.fileExists(atPath: olSyncPath) {
      externalWatches = []
      return
    }

    do {
      let result = try await ProcessRunner.run(
        executable: "/bin/ps",
        arguments: ["-axo", "pid=,command=", "-ww"],
        currentDirectory: root,
        environment: ProcessInfo.processInfo.environment
      )

      var byDir: [String: Set<Int32>] = [:]
      for rawLine in result.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }

        let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
        if parts.count < 2 { continue }
        guard let pid = Int32(parts[0]) else { continue }
        let cmd = String(parts[1])
        guard cmd.contains(olSyncPath) else { continue }
        guard cmd.contains(" watch ") else { continue }
        guard let dirRange = cmd.range(of: "--dir ") else { continue }

        let tail = cmd[dirRange.upperBound...]
        let dirStr = tail
          .split(whereSeparator: { $0 == " " || $0 == "\t" })
          .first
          .map(String.init)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if dirStr.isEmpty { continue }

        let resolved: String
        if dirStr.hasPrefix("~") {
          resolved = (dirStr as NSString).expandingTildeInPath
        } else if dirStr.hasPrefix("/") {
          resolved = dirStr
        } else {
          resolved = root.appendingPathComponent(dirStr).path
        }

        byDir[resolved, default: []].insert(pid)
      }

      let watches = byDir
        .map { (path, pids) in
          ExternalWatch(
            dir: URL(fileURLWithPath: path).standardizedFileURL,
            pids: pids.sorted()
          )
        }
        .sorted { $0.dir.path.localizedStandardCompare($1.dir.path) == .orderedAscending }

      externalWatches = watches
    } catch {
      appendLog("warn: failed to refresh external watches: \((error as NSError).localizedDescription)")
    }
  }

  func refreshStorageStatus() async {
    let configRoot = configRootURL()
    let host = hostKey(from: baseURL)
    let inboxDir = configRoot
      .appendingPathComponent("overleaf-sync")
      .appendingPathComponent("inbox")
      .appendingPathComponent(host)

    let snapshotsDir = configRoot
      .appendingPathComponent("overleaf-sync")
      .appendingPathComponent("snapshots")
      .appendingPathComponent(host)

    let keepLast = AppConstants.inboxKeepLastPerProject
    let keepAuto = AppConstants.autoSnapshotKeepLastPerProject

    let status = await Task.detached { () -> StorageStatus in
      var inboxProjects: [StorageStatus.InboxProject] = []
      var snapshotProjects: [StorageStatus.SnapshotProject] = []

      // Inbox
      do {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: inboxDir.path, isDirectory: &isDir), isDir.boolValue {
          let projectDirs = try FileManager.default.contentsOfDirectory(
            at: inboxDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
          )
          for projectDir in projectDirs {
            guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let projectId = projectDir.lastPathComponent
            let batchDirs = (try? FileManager.default.contentsOfDirectory(
              at: projectDir,
              includingPropertiesForKeys: [.isDirectoryKey],
              options: [.skipsHiddenFiles]
            )) ?? []
            let count = batchDirs.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.count
            inboxProjects.append(StorageStatus.InboxProject(projectId: projectId, batchCount: count, keepLast: keepLast))
          }
        }
      } catch {
        // ignore
      }

      // Snapshots
      do {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: snapshotsDir.path, isDirectory: &isDir), isDir.boolValue {
          let projectDirs = try FileManager.default.contentsOfDirectory(
            at: snapshotsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
          )
          for projectDir in projectDirs {
            guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let projectId = projectDir.lastPathComponent
            let batchDirs = (try? FileManager.default.contentsOfDirectory(
              at: projectDir,
              includingPropertiesForKeys: [.isDirectoryKey],
              options: [.skipsHiddenFiles]
            )) ?? []

            var pinned = 0
            var auto = 0
            for batchDir in batchDirs {
              guard (try? batchDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
              let keepMarker = batchDir.appendingPathComponent(".keep")
              if FileManager.default.fileExists(atPath: keepMarker.path) { pinned += 1 } else { auto += 1 }
            }
            snapshotProjects.append(StorageStatus.SnapshotProject(
              projectId: projectId,
              pinnedCount: pinned,
              autoCount: auto,
              keepAuto: keepAuto
            ))
          }
        }
      } catch {
        // ignore
      }

      inboxProjects.sort { $0.projectId.localizedStandardCompare($1.projectId) == .orderedAscending }
      snapshotProjects.sort { $0.projectId.localizedStandardCompare($1.projectId) == .orderedAscending }

      return StorageStatus(
        keepLast: keepLast,
        inboxProjects: inboxProjects,
        autoSnapshotKeepLast: keepAuto,
        snapshotProjects: snapshotProjects
      )
    }.value

    storageStatus = status
  }

  func prepareInboxCleanup(keepLast: Int = AppConstants.inboxKeepLastPerProject) async {
    let configRoot = configRootURL()
    let host = hostKey(from: baseURL)
    let inboxDir = configRoot
      .appendingPathComponent("overleaf-sync")
      .appendingPathComponent("inbox")
      .appendingPathComponent(host)

    let candidates = await Task.detached { () -> [String] in
      var toDelete: [String] = []
      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: inboxDir.path, isDirectory: &isDir),
            isDir.boolValue
      else { return [] }

      let projectDirs = (try? FileManager.default.contentsOfDirectory(
        at: inboxDir,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )) ?? []

      for projectDir in projectDirs {
        guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        let batches = (try? FileManager.default.contentsOfDirectory(
          at: projectDir,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        )) ?? []

        let batchDirs = batches
          .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
          .sorted { $0.lastPathComponent > $1.lastPathComponent } // newest first (timestamp-like)

        if batchDirs.count <= keepLast { continue }

        for dir in batchDirs.dropFirst(keepLast) {
          let keepMarker = dir.appendingPathComponent(".keep")
          if FileManager.default.fileExists(atPath: keepMarker.path) { continue }
          toDelete.append(dir.path)
        }
      }
      return toDelete
    }.value

    if candidates.isEmpty {
      alert = AlertItem(title: "No cleanup needed", message: "Inbox is within the keep-last-\(keepLast) limit.")
      await refreshStorageStatus()
      return
    }

    inboxCleanupPrompt = InboxCleanupPrompt(keepLast: keepLast, candidatePaths: candidates)
  }

  func confirmInboxCleanup(_ prompt: InboxCleanupPrompt) async {
    let removed = await Task.detached {
      var count = 0
      for path in prompt.candidatePaths {
        let dir = URL(fileURLWithPath: path)
        do {
          try FileManager.default.removeItem(at: dir)
          count += 1
        } catch {
          // best-effort cleanup
        }
      }
      return count
    }.value

    alert = AlertItem(
      title: "Inbox cleaned",
      message: "Removed \(removed) batch folder(s). Kept last \(prompt.keepLast) per project."
    )
    await refreshStorageStatus()
  }

  private func startExternalWatchPolling() {
    externalWatchPollTask?.cancel()
    externalWatchPollTask = Task {
      while !Task.isCancelled {
        await refreshExternalWatches()
        try? await Task.sleep(nanoseconds: 4_000_000_000)
      }
    }
  }

  private func startAutoRemoteFetchLoop() {
    autoRemoteFetchTask?.cancel()
    autoRemoteFetchTask = Task {
      while !Task.isCancelled {
        if autoRemoteFetchEnabled {
          await autoFetchRemoteChanges()
        }
        let minutes = max(1, autoRemoteFetchIntervalMinutes)
        try? await Task.sleep(nanoseconds: UInt64(minutes) * 60_000_000_000)
      }
    }
  }

  private func autoFetchRemoteChanges() async {
    guard workspaceRoot != nil else { return }
    guard !linkedFoldersByProjectId.isEmpty else { return }

    await refreshHistoryIndexes()

    // Avoid creating multiple pending batches per project; fetch only when there is no pending batch.
    let candidates = linkedFoldersByProjectId
      .filter { pendingRemoteBatchCount(for: $0.key) == 0 }
      .map { (projectId: $0.key, dir: $0.value) }
      .sorted { $0.projectId.localizedStandardCompare($1.projectId) == .orderedAscending }

    guard !candidates.isEmpty else { return }

    do {
      let client = try makeClient()
      for item in candidates {
        do {
          let manifest = try await client.fetch(
            baseURL: baseURL,
            dir: item.dir,
            skipEmpty: true,
            email: email.isEmpty ? nil : email,
            password: password.isEmpty ? nil : password
          )
          let saved = manifest.saved ?? true
          let a = manifest.changes.added.count
          let m = manifest.changes.modified.count
          let d = manifest.changes.deleted.count
          if saved, (a + m + d) > 0 {
            appendLog("auto-fetch: remote changes detected for \(item.dir.lastPathComponent) (added=\(a), modified=\(m), deleted=\(d))")
          }
        } catch {
          // Keep auto-fetch quiet; only log.
          appendLog("auto-fetch warn: \((error as NSError).localizedDescription)")
        }
      }
      await refreshHistoryIndexes()
      await refreshStorageStatus()
    } catch {
      appendLog("auto-fetch warn: \((error as NSError).localizedDescription)")
    }
  }

  private func configRootURL() -> URL {
    let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config").path
    return URL(fileURLWithPath: configHome)
  }

  private func hostKey(from baseURL: String) -> String {
    if let u = URL(string: baseURL), let host = u.host, !host.isEmpty {
      return host
    }
    return baseURL
      .replacingOccurrences(of: "https://", with: "")
      .replacingOccurrences(of: "http://", with: "")
      .replacingOccurrences(of: "/", with: "_")
  }

  private func inboxHostDir(baseURL: String) -> URL {
    configRootURL()
      .appendingPathComponent("overleaf-sync")
      .appendingPathComponent("inbox")
      .appendingPathComponent(hostKey(from: baseURL))
  }

  private func inboxBatchDir(baseURL: String, projectId: String, batchId: String) -> URL {
    inboxHostDir(baseURL: baseURL)
      .appendingPathComponent(projectId)
      .appendingPathComponent(batchId)
  }

  private func snapshotsHostDir(baseURL: String) -> URL {
    configRootURL()
      .appendingPathComponent("overleaf-sync")
      .appendingPathComponent("snapshots")
      .appendingPathComponent(hostKey(from: baseURL))
  }

  private func snapshotsProjectDir(baseURL: String, projectId: String) -> URL {
    snapshotsHostDir(baseURL: baseURL).appendingPathComponent(projectId)
  }

  func pendingRemoteBatchCount(for projectId: String) -> Int {
    (remoteInboxBatchesByProjectId[projectId] ?? []).filter { $0.state == .pending }.count
  }

  func pendingRemoteChangeCount(for projectId: String) -> Int {
    (remoteInboxBatchesByProjectId[projectId] ?? [])
      .filter { $0.state == .pending }
      .reduce(0) { $0 + $1.changeCount }
  }

  func refreshHistoryIndexes() async {
    let inboxDir = inboxHostDir(baseURL: baseURL)
    let snapshotsDir = snapshotsHostDir(baseURL: baseURL)

    let result = await Task.detached { () -> (inbox: [String: [RemoteInboxBatch]], snapshots: [String: [LocalSnapshotItem]]) in
      func parseISO(_ value: String) -> Date? {
        if let d = DateParsing.parseISO8601WithFractionalSeconds(value) { return d }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: value)
      }

      var inbox: [String: [RemoteInboxBatch]] = [:]
      var snapshots: [String: [LocalSnapshotItem]] = [:]
      let fm = FileManager.default

      // Inbox batches
      do {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: inboxDir.path, isDirectory: &isDir), isDir.boolValue {
          let projectDirs = (try? fm.contentsOfDirectory(
            at: inboxDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
          )) ?? []

          for projectDir in projectDirs {
            guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let projectId = projectDir.lastPathComponent
            let batchDirs = (try? fm.contentsOfDirectory(
              at: projectDir,
              includingPropertiesForKeys: [.isDirectoryKey],
              options: [.skipsHiddenFiles]
            )) ?? []

            var batches: [RemoteInboxBatch] = []
            for batchDir in batchDirs {
              guard (try? batchDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
              let manifestPath = batchDir.appendingPathComponent(AppConstants.inboxManifestFileName)
              guard fm.fileExists(atPath: manifestPath.path) else { continue }
              guard let data = try? Data(contentsOf: manifestPath) else { continue }
              guard let manifest = try? JSONDecoder().decode(OlSyncInboxManifest.self, from: data) else { continue }
              let added = manifest.changes.added.count
              let modified = manifest.changes.modified.count
              let deleted = manifest.changes.deleted.count
              let changeCount = added + modified + deleted
              if changeCount == 0 { continue }

              let appliedMarker = batchDir.appendingPathComponent(AppConstants.inboxAppliedMarkerFileName)
              let state: RemoteInboxBatch.State = fm.fileExists(atPath: appliedMarker.path) ? .applied : .pending
              let createdAt = parseISO(manifest.createdAt)
              batches.append(RemoteInboxBatch(
                projectId: projectId,
                batchId: manifest.batchId,
                createdAt: createdAt,
                addedCount: added,
                modifiedCount: modified,
                deletedCount: deleted,
                state: state,
                dir: batchDir
              ))
            }

            batches.sort { $0.batchId > $1.batchId }
            if !batches.isEmpty {
              inbox[projectId] = batches
            }
          }
        }
      }

      // Local snapshots
      do {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: snapshotsDir.path, isDirectory: &isDir), isDir.boolValue {
          let projectDirs = (try? fm.contentsOfDirectory(
            at: snapshotsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
          )) ?? []

          for projectDir in projectDirs {
            guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let projectId = projectDir.lastPathComponent
            let snapshotDirs = (try? fm.contentsOfDirectory(
              at: projectDir,
              includingPropertiesForKeys: [.isDirectoryKey],
              options: [.skipsHiddenFiles]
            )) ?? []

            var items: [LocalSnapshotItem] = []
            for snapshotDir in snapshotDirs {
              guard (try? snapshotDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
              let manifestPath = snapshotDir.appendingPathComponent(AppConstants.snapshotManifestFileName)
              guard fm.fileExists(atPath: manifestPath.path) else { continue }
              guard let data = try? Data(contentsOf: manifestPath) else { continue }
              guard let manifest = try? JSONDecoder().decode(LocalSnapshotManifest.self, from: data) else { continue }
              let keep = snapshotDir.appendingPathComponent(AppConstants.snapshotPinnedMarkerFileName)
              let isPinned = fm.fileExists(atPath: keep.path)
              let createdAt = parseISO(manifest.createdAt)
              items.append(LocalSnapshotItem(
                projectId: projectId,
                createdAt: createdAt,
                note: manifest.note,
                isPinned: isPinned,
                dir: snapshotDir
              ))
            }

            items.sort { ($0.createdAt?.timeIntervalSince1970 ?? 0) > ($1.createdAt?.timeIntervalSince1970 ?? 0) }
            if !items.isEmpty {
              snapshots[projectId] = items
            }
          }
        }
      }

      return (inbox, snapshots)
    }.value

    remoteInboxBatchesByProjectId = result.inbox
    localSnapshotsByProjectId = result.snapshots
    await refreshSelectedProjectHistory()
  }

  func refreshSelectedProjectHistory() async {
    guard let pid = selectedProjectId else {
      selectedProjectInboxBatches = []
      selectedProjectSnapshots = []
      return
    }
    selectedProjectInboxBatches = remoteInboxBatchesByProjectId[pid] ?? []
    selectedProjectSnapshots = localSnapshotsByProjectId[pid] ?? []
  }

  func prepareLocalSnapshotsCleanup(keepLastAuto: Int = AppConstants.autoSnapshotKeepLastPerProject) async {
    let configRoot = configRootURL()
    let host = hostKey(from: baseURL)
    let snapshotsDir = configRoot
      .appendingPathComponent("overleaf-sync")
      .appendingPathComponent("snapshots")
      .appendingPathComponent(host)

    let candidates = await Task.detached { () -> [String] in
      var toDelete: [String] = []
      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: snapshotsDir.path, isDirectory: &isDir),
            isDir.boolValue
      else { return [] }

      let projectDirs = (try? FileManager.default.contentsOfDirectory(
        at: snapshotsDir,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )) ?? []

      for projectDir in projectDirs {
        guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        let batches = (try? FileManager.default.contentsOfDirectory(
          at: projectDir,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        )) ?? []

        let autoBatches = batches
          .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
          .filter { !FileManager.default.fileExists(atPath: $0.appendingPathComponent(".keep").path) }
          .sorted { $0.lastPathComponent > $1.lastPathComponent } // newest first

        if autoBatches.count <= keepLastAuto { continue }
        for dir in autoBatches.dropFirst(keepLastAuto) {
          toDelete.append(dir.path)
        }
      }

      return toDelete
    }.value

    if candidates.isEmpty {
      alert = AlertItem(
        title: "No cleanup needed",
        message: "Auto snapshots are within the keep-last-\(keepLastAuto) limit."
      )
      await refreshStorageStatus()
      return
    }

    localSnapshotsCleanupPrompt = LocalSnapshotsCleanupPrompt(keepLastAuto: keepLastAuto, candidatePaths: candidates)
  }

  func confirmLocalSnapshotsCleanup(_ prompt: LocalSnapshotsCleanupPrompt) async {
    let removed = await Task.detached {
      var count = 0
      for path in prompt.candidatePaths {
        let dir = URL(fileURLWithPath: path)
        do {
          try FileManager.default.removeItem(at: dir)
          count += 1
        } catch {
          // best-effort cleanup
        }
      }
      return count
    }.value

    alert = AlertItem(
      title: "Local snapshots cleaned",
      message: "Removed \(removed) auto snapshot folder(s). Kept last \(prompt.keepLastAuto) auto snapshots per project."
    )
    await refreshStorageStatus()
  }

  func openInboxFolder() {
    let dir = configRootURL()
      .appendingPathComponent("overleaf-sync")
      .appendingPathComponent("inbox")
      .appendingPathComponent(hostKey(from: baseURL))
    NSWorkspace.shared.open(dir)
  }

  func openBackupsFolder() {
    let dir = configRootURL()
      .appendingPathComponent("overleaf-sync")
      .appendingPathComponent("backups")
      .appendingPathComponent(hostKey(from: baseURL))
    NSWorkspace.shared.open(dir)
  }

  func openSnapshotsRootFolder() {
    let dir = configRootURL()
      .appendingPathComponent("overleaf-sync")
      .appendingPathComponent("snapshots")
      .appendingPathComponent(hostKey(from: baseURL))
    NSWorkspace.shared.open(dir)
  }

  func openSnapshotsFolder() {
    guard let cfg = localFolderConfig, let pid = cfg.projectId, !pid.isEmpty else {
      alert = AlertItem(title: "Not linked", message: "Choose a linked project folder first.")
      return
    }
    let effectiveBase = cfg.baseUrl ?? baseURL
    let dir = configRootURL()
      .appendingPathComponent("overleaf-sync")
      .appendingPathComponent("snapshots")
      .appendingPathComponent(hostKey(from: effectiveBase))
      .appendingPathComponent(pid)
    NSWorkspace.shared.open(dir)
  }

  func openSnapshotsFolderForSelectedProject() {
    guard let pid = selectedProjectId, !pid.isEmpty else {
      alert = AlertItem(title: "Missing project", message: "Select a project first.")
      return
    }
    let dir = snapshotsProjectDir(baseURL: baseURL, projectId: pid)
    NSWorkspace.shared.open(dir)
  }

  func saveAutoSnapshot(note: String? = nil) async {
    guard let dir = localFolder else {
      alert = AlertItem(title: "Missing folder", message: "Choose a local folder first.")
      return
    }
    guard let cfg = localFolderConfig, let pid = cfg.projectId, !pid.isEmpty else {
      alert = AlertItem(title: "Not linked", message: "This folder is not linked yet. Link it first.")
      return
    }
    await saveSnapshot(
      pinned: false,
      note: note,
      dir: dir,
      projectId: pid,
      effectiveBase: cfg.baseUrl ?? baseURL
    )
    await refreshHistoryIndexes()
    await refreshStorageStatus()
  }

  func savePinnedSnapshot(note: String? = nil) async {
    guard let dir = localFolder else {
      alert = AlertItem(title: "Missing folder", message: "Choose a local folder first.")
      return
    }
    guard let cfg = localFolderConfig, let pid = cfg.projectId, !pid.isEmpty else {
      alert = AlertItem(title: "Not linked", message: "This folder is not linked yet. Link it first.")
      return
    }
    await saveSnapshot(
      pinned: true,
      note: note,
      dir: dir,
      projectId: pid,
      effectiveBase: cfg.baseUrl ?? baseURL
    )
    await refreshHistoryIndexes()
    await refreshStorageStatus()
  }

  func saveAutoSnapshotForSelectedProject(note: String? = nil) async {
    guard let project = selectedProject else {
      alert = AlertItem(title: "Missing project", message: "Select a project first.")
      return
    }
    guard let dir = linkedFolder(for: project.id) else {
      alert = AlertItem(title: "Not linked", message: "No linked local folder found for this project.")
      return
    }
    let cfg = readConfig(in: dir)
    let pid = cfg?.projectId ?? project.id
    let effectiveBase = cfg?.baseUrl ?? baseURL
    await saveSnapshot(pinned: false, note: note, dir: dir, projectId: pid, effectiveBase: effectiveBase)
    await refreshHistoryIndexes()
    await refreshStorageStatus()
  }

  func savePinnedSnapshotForSelectedProject(note: String? = nil) async {
    guard let project = selectedProject else {
      alert = AlertItem(title: "Missing project", message: "Select a project first.")
      return
    }
    guard let dir = linkedFolder(for: project.id) else {
      alert = AlertItem(title: "Not linked", message: "No linked local folder found for this project.")
      return
    }
    let cfg = readConfig(in: dir)
    let pid = cfg?.projectId ?? project.id
    let effectiveBase = cfg?.baseUrl ?? baseURL
    await saveSnapshot(pinned: true, note: note, dir: dir, projectId: pid, effectiveBase: effectiveBase)
    await refreshHistoryIndexes()
    await refreshStorageStatus()
  }

  private func saveSnapshot(pinned: Bool, note: String?, dir: URL, projectId: String, effectiveBase: String) async {
    let configRoot = configRootURL()
    let host = hostKey(from: effectiveBase)

    let tsFmt = ISO8601DateFormatter()
    tsFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let ts = tsFmt.string(from: Date())
      .replacingOccurrences(of: ":", with: "-")
      .replacingOccurrences(of: ".", with: "-")

    let snapshotDir = configRoot
      .appendingPathComponent("overleaf-sync")
      .appendingPathComponent("snapshots")
      .appendingPathComponent(host)
      .appendingPathComponent(projectId)
      .appendingPathComponent(ts)

    let result = await Task.detached { () -> (Bool, String, String?) in
      let fm = FileManager.default
      let filesDir = snapshotDir.appendingPathComponent("files")
      do {
        try fm.createDirectory(at: filesDir, withIntermediateDirectories: true)

        let excluded: Set<String> = [".git", ".DS_Store", ".Trash", ".Spotlight-V100"]

        func copyTree(from src: URL, to dst: URL) throws {
          var isDir: ObjCBool = false
          guard fm.fileExists(atPath: src.path, isDirectory: &isDir) else { return }
          if isDir.boolValue {
            try fm.createDirectory(at: dst, withIntermediateDirectories: true)
            let children = try fm.contentsOfDirectory(
              at: src,
              includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
              options: []
            )
            for child in children {
              let name = child.lastPathComponent
              if excluded.contains(name) { continue }
              let childDst = dst.appendingPathComponent(name)
              try copyTree(from: child, to: childDst)
            }
          } else {
            if fm.fileExists(atPath: dst.path) {
              try? fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)
          }
        }

        try copyTree(from: dir, to: filesDir.appendingPathComponent(dir.lastPathComponent))

        let manifest = LocalSnapshotManifest(
          version: 1,
          createdAt: ts,
          projectId: projectId,
          baseUrl: effectiveBase,
          localDir: dir.path,
          snapshotDir: snapshotDir.path,
          note: note
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: snapshotDir.appendingPathComponent(".ol-sync.snapshot.json"))
        if pinned {
          try Data().write(to: snapshotDir.appendingPathComponent(".keep"))
        }
        return (true, snapshotDir.path, nil as String?)
      } catch {
        return (false, snapshotDir.path, (error as NSError).localizedDescription)
      }
    }.value

    if result.0 {
      let kind = pinned ? "Pinned" : "Auto"
      alert = AlertItem(title: "Snapshot saved", message: "\(kind) snapshot created at:\n\(result.1)")
    } else {
      alert = AlertItem(title: "Snapshot failed", message: result.2 ?? "Unknown error")
    }
  }

  private func applyLaunchArguments() {
    func value(after flag: String) -> String? {
      let args = CommandLine.arguments
      guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
      return args[i + 1]
    }

    if let path = value(after: "--workspace-root"), !path.isEmpty {
      let url = URL(fileURLWithPath: path)
      workspaceRoot = url
      Preferences.setPath(url, forKey: Preferences.Key.workspaceRoot)
    }
    if let url = value(after: "--base-url"), !url.isEmpty {
      baseURL = url
      Preferences.setString(url, forKey: Preferences.Key.baseURL)
    }
  }

  func fetchRemoteChanges() async {
    guard let dir = localFolder else {
      alert = AlertItem(title: "Missing folder", message: "Choose a local folder first.")
      return
    }
    guard let cfg = localFolderConfig, let pid = cfg.projectId, !pid.isEmpty else {
      alert = AlertItem(
        title: "Not linked",
        message: "This folder is not linked yet. Run Link (or Pull) to create .ol-sync.json first."
      )
      return
    }
    if let selectedProjectId, selectedProjectId != pid {
      alert = AlertItem(
        title: "Folder mismatch",
        message: "Local folder is linked to a different project. Choose the correct folder (or click Use) before fetching remote changes."
      )
      return
    }

    do {
      let client = try makeClient()
      appendLog("→ fetch (remote snapshot) \(dir.path)")
      let manifest = try await client.fetch(
        baseURL: baseURL,
        dir: dir,
        skipEmpty: true,
        email: email.isEmpty ? nil : email,
        password: password.isEmpty ? nil : password
      )
      remoteManifest = manifest
      let a = manifest.changes.added.count
      let m = manifest.changes.modified.count
      let d = manifest.changes.deleted.count
      let saved = manifest.saved ?? true
      if saved, (a + m + d) > 0 {
        alert = AlertItem(
          title: "Remote changes found",
          message: "added=\(a), modified=\(m), deleted=\(d)\nBatch: \(manifest.batchId)"
        )
      } else {
        alert = AlertItem(title: "No remote changes", message: "Remote matches local.")
      }
      await refreshHistoryIndexes()
      await refreshStorageStatus()
    } catch {
      handleCommandError(error)
    }
  }

  func prepareApplyRemoteChanges() async {
    guard let dir = localFolder else {
      alert = AlertItem(title: "Missing folder", message: "Choose a local folder first.")
      return
    }
    guard let cfg = localFolderConfig, let pid = cfg.projectId, !pid.isEmpty else {
      alert = AlertItem(
        title: "Not linked",
        message: "This folder is not linked yet. Run Link (or Pull) to create .ol-sync.json first."
      )
      return
    }
    if let selectedProjectId, selectedProjectId != pid {
      alert = AlertItem(
        title: "Folder mismatch",
        message: "Local folder is linked to a different project. Choose the correct folder (or click Use) before applying remote changes."
      )
      return
    }

    do {
      let client = try makeClient()
      appendLog("→ fetch --json (before apply) \(dir.path)")
      let manifest = try await client.fetch(
        baseURL: baseURL,
        dir: dir,
        skipEmpty: true,
        email: email.isEmpty ? nil : email,
        password: password.isEmpty ? nil : password
      )
      remoteManifest = manifest

      let a = manifest.changes.added.count
      let m = manifest.changes.modified.count
      let d = manifest.changes.deleted.count
      if a == 0, m == 0, d == 0 {
        alert = AlertItem(title: "No remote changes", message: "Remote matches local.")
        return
      }

      remoteApplyPrompt = RemoteApplyPrompt(
        dir: dir,
        projectId: pid,
        batchId: manifest.batchId,
        added: a,
        modified: m,
        deleted: d
      )
    } catch {
      handleCommandError(error)
    }
  }

  func confirmApplyRemoteChanges(_ prompt: RemoteApplyPrompt) async {
    do {
      let client = try makeClient()
      appendLog("→ apply --batch \(prompt.batchId) \(prompt.dir.path)")
      let result = try await client.apply(
        baseURL: baseURL,
        dir: prompt.dir,
        batchId: prompt.batchId,
        email: email.isEmpty ? nil : email,
        password: password.isEmpty ? nil : password
      )
      appendLog(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
      do {
        let marker = inboxBatchDir(baseURL: baseURL, projectId: prompt.projectId, batchId: prompt.batchId)
          .appendingPathComponent(AppConstants.inboxAppliedMarkerFileName)
        let appliedAt = ISO8601DateFormatter().string(from: Date())
        try Data((appliedAt + "\n").utf8).write(to: marker)
      } catch {
        // best-effort marker
      }
      alert = AlertItem(
        title: "Applied remote changes",
        message: "Applied added=\(prompt.added), modified=\(prompt.modified). (No local deletions.)"
      )
      await refreshHistoryIndexes()
      await refreshStorageStatus()
    } catch {
      handleCommandError(error)
    }
  }

  private func linkedFolder(for projectId: String) -> URL? {
    if let dir = linkedFoldersByProjectId[projectId] {
      return dir
    }
    if let dir = localFolder, let cfg = localFolderConfig, cfg.projectId == projectId {
      return dir
    }
    return nil
  }

  func fetchRemoteChangesForSelectedProject(notify: Bool = true) async {
    guard let project = selectedProject else {
      alert = AlertItem(title: "Missing project", message: "Select a project first.")
      return
    }
    guard let dir = linkedFolder(for: project.id) else {
      alert = AlertItem(title: "Not linked", message: "No linked local folder found for this project.")
      return
    }
    if pendingRemoteBatchCount(for: project.id) > 0 {
      if notify {
        alert = AlertItem(
          title: "Already fetched",
          message: "There is already a pending inbox batch for this project. Apply it first (Remote tab → Apply latest…)."
        )
      }
      return
    }

    do {
      let client = try makeClient()
      appendLog("→ fetch --skip-empty \(dir.path)")
      let manifest = try await client.fetch(
        baseURL: baseURL,
        dir: dir,
        skipEmpty: true,
        email: email.isEmpty ? nil : email,
        password: password.isEmpty ? nil : password
      )
      remoteManifest = manifest

      await refreshHistoryIndexes()
      await refreshStorageStatus()

      if notify {
        let a = manifest.changes.added.count
        let m = manifest.changes.modified.count
        let d = manifest.changes.deleted.count
        let saved = manifest.saved ?? true
        if saved, (a + m + d) > 0 {
          alert = AlertItem(
            title: "Remote changes found",
            message: "added=\(a), modified=\(m), deleted=\(d)\nBatch: \(manifest.batchId)"
          )
        } else {
          alert = AlertItem(title: "No remote changes", message: "Remote matches local.")
        }
      }
    } catch {
      handleCommandError(error)
    }
  }

  func prepareApplyLatestRemoteChangesForSelectedProject() async {
    guard let project = selectedProject else {
      alert = AlertItem(title: "Missing project", message: "Select a project first.")
      return
    }
    guard let dir = linkedFolder(for: project.id) else {
      alert = AlertItem(title: "Not linked", message: "No linked local folder found for this project.")
      return
    }

    if let pending = (remoteInboxBatchesByProjectId[project.id] ?? []).first(where: { $0.state == .pending }) {
      remoteApplyPrompt = RemoteApplyPrompt(
        dir: dir,
        projectId: project.id,
        batchId: pending.batchId,
        added: pending.addedCount,
        modified: pending.modifiedCount,
        deleted: pending.deletedCount
      )
      return
    }

    // No pending batch yet: fetch once, then apply the freshly created batch (if any).
    do {
      let client = try makeClient()
      appendLog("→ fetch --skip-empty (for apply) \(dir.path)")
      let manifest = try await client.fetch(
        baseURL: baseURL,
        dir: dir,
        skipEmpty: true,
        email: email.isEmpty ? nil : email,
        password: password.isEmpty ? nil : password
      )
      remoteManifest = manifest

      let a = manifest.changes.added.count
      let m = manifest.changes.modified.count
      let d = manifest.changes.deleted.count
      let saved = manifest.saved ?? true
      if !saved || (a + m + d) == 0 {
        alert = AlertItem(title: "No remote changes", message: "Remote matches local.")
        await refreshHistoryIndexes()
        await refreshStorageStatus()
        return
      }

      remoteApplyPrompt = RemoteApplyPrompt(
        dir: dir,
        projectId: project.id,
        batchId: manifest.batchId,
        added: a,
        modified: m,
        deleted: d
      )
      await refreshHistoryIndexes()
      await refreshStorageStatus()
    } catch {
      handleCommandError(error)
    }
  }

  func openInboxBatchFolder(_ batch: RemoteInboxBatch) {
    NSWorkspace.shared.open(batch.dir)
  }

  func prepareApplyInboxBatch(_ batch: RemoteInboxBatch) {
    guard let dir = linkedFolder(for: batch.projectId) else {
      alert = AlertItem(title: "Not linked", message: "No linked local folder found for this project.")
      return
    }
    remoteApplyPrompt = RemoteApplyPrompt(
      dir: dir,
      projectId: batch.projectId,
      batchId: batch.batchId,
      added: batch.addedCount,
      modified: batch.modifiedCount,
      deleted: batch.deletedCount
    )
  }

  func openSnapshotFolder(_ snapshot: LocalSnapshotItem) {
    NSWorkspace.shared.open(snapshot.dir)
  }

  func prepareRestoreSnapshot(_ snapshot: LocalSnapshotItem) {
    guard let dir = linkedFolder(for: snapshot.projectId) else {
      alert = AlertItem(title: "Not linked", message: "No linked local folder found for this project.")
      return
    }
    snapshotRestorePrompt = SnapshotRestorePrompt(snapshot: snapshot, targetDir: dir)
  }

  func confirmRestoreSnapshot(_ prompt: SnapshotRestorePrompt) async {
    let snapshotDir = prompt.snapshot.dir
    let targetDir = prompt.targetDir

    let effectiveBase = baseURL
    let host = hostKey(from: effectiveBase)

    let restoreId = snapshotDir.lastPathComponent
    let backupRoot = configRootURL()
      .appendingPathComponent("overleaf-sync")
      .appendingPathComponent("backups")
      .appendingPathComponent(host)
      .appendingPathComponent(prompt.snapshot.projectId)
      .appendingPathComponent("snapshot-restore")
      .appendingPathComponent(restoreId)

    let result = await Task.detached { () -> (Bool, Int, String?) in
      let fm = FileManager.default
      let filesRoot = snapshotDir.appendingPathComponent("files")
      do {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: filesRoot.path, isDirectory: &isDir), isDir.boolValue else {
          return (false, 0, "Snapshot files folder is missing: \(filesRoot.path)")
        }

        let roots = (try? fm.contentsOfDirectory(
          at: filesRoot,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        )) ?? []
        guard let snapshotRoot = roots.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) else {
          return (false, 0, "Snapshot root folder not found under: \(filesRoot.path)")
        }

        try fm.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        let excluded: Set<String> = [".git", ".DS_Store", ".Trash", ".Spotlight-V100"]

        func walk(_ dir: URL) throws -> [URL] {
          let entries = try fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
          )
          var out: [URL] = []
          for e in entries {
            let name = e.lastPathComponent
            if excluded.contains(name) { continue }
            let vals = try e.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if vals.isSymbolicLink == true { continue }
            if vals.isDirectory == true {
              out.append(contentsOf: try walk(e))
            } else {
              out.append(e)
            }
          }
          return out
        }

        let files = try walk(snapshotRoot)
        var restored = 0
        for src in files {
          let rel = src.path.replacingOccurrences(of: snapshotRoot.path + "/", with: "")
          let dst = targetDir.appendingPathComponent(rel)
          let backupPath = backupRoot.appendingPathComponent(rel)

          if fm.fileExists(atPath: dst.path) {
            var isDir2: ObjCBool = false
            if fm.fileExists(atPath: dst.path, isDirectory: &isDir2), !isDir2.boolValue {
              try fm.createDirectory(at: backupPath.deletingLastPathComponent(), withIntermediateDirectories: true)
              try? fm.removeItem(at: backupPath)
              try fm.copyItem(at: dst, to: backupPath)
            }
          }

          try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
          if fm.fileExists(atPath: dst.path) {
            try? fm.removeItem(at: dst)
          }
          try fm.copyItem(at: src, to: dst)
          restored += 1
        }

        return (true, restored, nil)
      } catch {
        return (false, 0, (error as NSError).localizedDescription)
      }
    }.value

    if result.0 {
      alert = AlertItem(
        title: "Snapshot restored",
        message: "Restored \(result.1) file(s).\nBackup: \(backupRoot.path)"
      )
    } else {
      alert = AlertItem(title: "Restore failed", message: result.2 ?? "Unknown error")
    }
  }

  func prepareMoveRootConfigAside() {
    guard let root = projectsRoot, localFolder == root else { return }
    guard let cfg = localFolderConfig else { return }
    rootConfigPrompt = RootConfigPrompt(dir: root, projectId: cfg.projectId)
  }

  func confirmMoveRootConfigAside(_ prompt: RootConfigPrompt) {
    let src = configPath(in: prompt.dir)
    guard FileManager.default.fileExists(atPath: src.path) else {
      alert = AlertItem(title: "Nothing to fix", message: "No .ol-sync.json found in this folder.")
      return
    }
    let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
    let dst = prompt.dir.appendingPathComponent("\(Self.configFileName).bak.\(ts)")

    do {
      try FileManager.default.moveItem(at: src, to: dst)
      appendLog("moved root config: \(src.path) -> \(dst.path)")
      reloadLocalFolderConfig()
      refreshLocalIndex()
      alert = AlertItem(title: "Fixed", message: "Moved root .ol-sync.json to:\n\(dst.lastPathComponent)")
    } catch {
      alert = AlertItem(title: "Fix failed", message: (error as NSError).localizedDescription)
    }
  }

  // MARK: - Internal watch helper

  private func startWatch(for dir: URL) throws -> Bool {
    if let existing = watches.first(where: { $0.dir == dir && $0.isRunning }) {
      selectedWatchSelection = .internal(existing.id)
      return false
    }
    if let ext = externalWatches.first(where: { $0.dir.standardizedFileURL == dir.standardizedFileURL && !$0.pids.isEmpty }) {
      selectedWatchSelection = .external(ext.id)
      return false
    }

    let task = try WatchTask.start(
      title: dir.lastPathComponent,
      workspaceRoot: try requireWorkspaceRoot(),
      baseURL: baseURL,
      dir: dir,
      credentials: currentCredentials()
    )
    task.onEvent = { [weak self] event in
      Task { @MainActor in
        self?.appendLog(event)
      }
    }
    task.onExit = { [weak self] in
      Task { @MainActor in
        self?.appendLog("watch exited: \(dir.path)")
      }
    }

    watches.append(task)
    selectedWatchSelection = .internal(task.id)
    appendLog("→ watch \(dir.path)")
    return true
  }
}

struct OverwritePrompt: Identifiable, Hashable {
  enum Kind: Hashable {
    case link
    case create
  }

  let id = UUID()
  let kind: Kind
  let dir: URL
  let existingProjectId: String?
  let targetProjectId: String?
}

struct RemoteApplyPrompt: Identifiable, Hashable {
  let id = UUID()
  let dir: URL
  let projectId: String
  let batchId: String
  let added: Int
  let modified: Int
  let deleted: Int
}

struct RootConfigPrompt: Identifiable, Hashable {
  let id = UUID()
  let dir: URL
  let projectId: String?
}

struct NewFolderPrompt: Identifiable, Hashable {
  let id = UUID()
  let parent: URL
}

struct SnapshotRestorePrompt: Identifiable, Hashable {
  let id = UUID()
  let snapshot: LocalSnapshotItem
  let targetDir: URL
}
