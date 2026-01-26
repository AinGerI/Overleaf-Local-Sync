import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
  static let configFileName = ".ol-sync.json"

  @Published var workspaceRoot: URL? {
    didSet {
      Preferences.setPath(workspaceRoot, forKey: Preferences.Key.workspaceRoot)
      refreshLocalIndex()
    }
  }

  @Published var baseURL: String {
    didSet { Preferences.setString(baseURL, forKey: Preferences.Key.baseURL) }
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
  @Published var selectedProjectId: Project.ID?

  @Published var watches: [WatchTask] = []
  @Published var selectedWatchId: WatchTask.ID?

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

  init() {
    self.workspaceRoot = Preferences.getPath(forKey: Preferences.Key.workspaceRoot)
    self.baseURL = Preferences.getString(forKey: Preferences.Key.baseURL) ?? "http://localhost"
    self.email = Preferences.getString(forKey: Preferences.Key.email) ?? ""
    self.localFolder = Preferences.getPath(forKey: Preferences.Key.localFolder)
    self.pullParentFolder = Preferences.getPath(forKey: Preferences.Key.pullParentFolder)

    reloadLocalFolderConfig()
    refreshLocalIndex()
  }

  var selectedProject: Project? {
    guard let selectedProjectId else { return nil }
    return projects.first(where: { $0.id == selectedProjectId })
  }

  var selectedWatch: WatchTask? {
    guard let selectedWatchId else { return nil }
    return watches.first(where: { $0.id == selectedWatchId })
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
      _ = try startWatch(for: dir)
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
    guard let watch = selectedWatch else { return }
    watch.stop()
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
        email: email.isEmpty ? nil : email,
        password: password.isEmpty ? nil : password
      )
      remoteManifest = manifest
      let a = manifest.changes.added.count
      let m = manifest.changes.modified.count
      let d = manifest.changes.deleted.count
      alert = AlertItem(
        title: "Remote snapshot fetched",
        message: "added=\(a), modified=\(m), deleted=\(d)\nBatch: \(manifest.batchId)"
      )
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
      alert = AlertItem(
        title: "Applied remote changes",
        message: "Applied added=\(prompt.added), modified=\(prompt.modified). (No local deletions.)"
      )
    } catch {
      handleCommandError(error)
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
      selectedWatchId = existing.id
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
    selectedWatchId = task.id
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
