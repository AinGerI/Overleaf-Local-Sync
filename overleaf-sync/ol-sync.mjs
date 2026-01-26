import {
  chmod,
  copyFile,
  mkdir,
  readFile,
  readdir,
  rename,
  stat,
  writeFile,
} from 'node:fs/promises'
import { createWriteStream } from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import process from 'node:process'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import readline from 'node:readline'
import { Readable } from 'node:stream'
import { pipeline } from 'node:stream/promises'
import { createHash } from 'node:crypto'

import {
  CookieJar,
  DEFAULT_BASE_URL,
  DEFAULT_CONTAINER,
  CONFIG_FILENAME,
  extractCsrfToken as extractCsrfTokenFromHtml,
  shouldIgnore,
  toPosix,
  basicAuthHeader,
} from './lib.mjs'

const execFileAsync = promisify(execFile)
const DEFAULT_SESSION_PATH = path.join(
  os.homedir(),
  '.config',
  'overleaf-sync',
  'session.json'
)
const DEFAULT_MONGO_CONTAINER = 'mongo'
const DEFAULT_INBOX_ROOT = path.join(os.homedir(), '.config', 'overleaf-sync', 'inbox')
const DEFAULT_BACKUP_ROOT = path.join(os.homedir(), '.config', 'overleaf-sync', 'backups')

function normalizeBaseUrl(baseUrl) {
  return String(baseUrl || '').replace(/\/+$/, '')
}

function resolveSessionPath(opts) {
  return (
    opts?.['session-path'] ||
    process.env.OVERLEAF_SYNC_SESSION_PATH ||
    DEFAULT_SESSION_PATH
  )
}

async function loadSessionStore(sessionPath) {
  try {
    const raw = await readFile(sessionPath, 'utf8')
    const parsed = JSON.parse(raw)
    if (!parsed || typeof parsed !== 'object') {
      return { version: 1, sessions: {} }
    }
    return {
      version: 1,
      sessions: parsed.sessions && typeof parsed.sessions === 'object' ? parsed.sessions : {},
    }
  } catch {
    return { version: 1, sessions: {} }
  }
}

async function saveSessionStore(sessionPath, store) {
  await mkdir(path.dirname(sessionPath), { recursive: true })
  const tmpPath = `${sessionPath}.tmp-${process.pid}-${Date.now()}`
  await writeFile(tmpPath, JSON.stringify(store, null, 2) + '\n', {
    encoding: 'utf8',
    mode: 0o600,
  })
  await rename(tmpPath, sessionPath)
  try {
    await chmod(sessionPath, 0o600)
  } catch {
    // best-effort on non-POSIX filesystems
  }
}

async function loadCachedSession(baseUrl, sessionPath) {
  const normalized = normalizeBaseUrl(baseUrl)
  const store = await loadSessionStore(sessionPath)
  const entry = store.sessions?.[normalized]
  if (!entry || typeof entry !== 'object') return null
  const jar = CookieJar.fromObject(entry.cookies || {})
  const csrfToken = typeof entry.csrfToken === 'string' ? entry.csrfToken : ''
  return { jar, csrfToken }
}

async function saveCachedSession(baseUrl, sessionPath, session) {
  const normalized = normalizeBaseUrl(baseUrl)
  const store = await loadSessionStore(sessionPath)
  store.sessions[normalized] = {
    cookies: session.jar.toObject(),
    csrfToken: session.csrfToken,
    savedAt: new Date().toISOString(),
  }
  await saveSessionStore(sessionPath, store)
}

async function refreshCsrfToken(baseUrl, session) {
  const normalized = normalizeBaseUrl(baseUrl)
  const { body } = await readText(`${normalized}/login`, session.jar)
  const csrf = extractCsrfTokenFromHtml(body)
  if (!csrf) {
    throw new Error('Could not find CSRF token on /login')
  }
  session.csrfToken = csrf
}

async function ensureAuthenticated(baseUrl, opts, { requireUserInfo } = {}) {
  const normalized = normalizeBaseUrl(baseUrl)
  const sessionPath = resolveSessionPath(opts)
  const noSessionCache = Boolean(opts?.['no-session-cache'])

  if (!noSessionCache) {
    const cached = await loadCachedSession(normalized, sessionPath)
    if (cached) {
      try {
        await refreshCsrfToken(normalized, cached)
        let me = null
        if (requireUserInfo) {
          me = await getPersonalInfo(normalized, cached)
        }
        await saveCachedSession(normalized, sessionPath, cached)
        return { session: cached, me, reusedSession: true, sessionPath }
      } catch {
        // fall through to password login
      }
    }
  }

  const providedEmail =
    (typeof opts?.email === 'string' && opts.email.trim()) ||
    (typeof process.env.OVERLEAF_SYNC_EMAIL === 'string' &&
      process.env.OVERLEAF_SYNC_EMAIL.trim()) ||
    (typeof process.env.OVERLEAF_EMAIL === 'string' &&
      process.env.OVERLEAF_EMAIL.trim()) ||
    ''
  const providedPassword =
    (typeof opts?.password === 'string' && opts.password) ||
    process.env.OVERLEAF_SYNC_PASSWORD ||
    process.env.OVERLEAF_PASSWORD ||
    ''

  if (!providedEmail && !process.stdin.isTTY) {
    throw new Error(
      'Cannot prompt for Overleaf email (non-interactive). Provide --email or set OVERLEAF_SYNC_EMAIL.'
    )
  }
  const email = providedEmail || (await promptLine('Overleaf email: '))
  if (!email) {
    throw new Error('Missing email for login.')
  }
  const password =
    providedPassword ||
    (process.stdin.isTTY
      ? await promptHidden('Overleaf password: ')
      : '')
  if (!password) {
    throw new Error(
      'Cannot prompt for Overleaf password (non-interactive). Provide --password or set OVERLEAF_SYNC_PASSWORD.'
    )
  }
  const session = await login(normalized, email, password)
  const me = requireUserInfo ? await getPersonalInfo(normalized, session) : null

  if (!noSessionCache) {
    await saveCachedSession(normalized, sessionPath, session)
    process.stdout.write(`Session cached at ${sessionPath}\\n`)
  }

  return { session, me, reusedSession: false, sessionPath }
}

function usage(exitCode = 0) {
  const text = `
Usage:
  node overleaf-sync/ol-sync.mjs projects [--base-url http://localhost] [--active-only] [--debug] [--json]
  node overleaf-sync/ol-sync.mjs link --project-id <id> --dir <path> [--base-url ...] [--mongo-container mongo] [--container sharelatex] [--force]
  node overleaf-sync/ol-sync.mjs create --dir <path> [--name <projectName>] [--base-url ...] [--mongo-container mongo] [--force]
  node overleaf-sync/ol-sync.mjs pull --project-id <id> --dir <path> [--base-url ...] [--mongo-container mongo]
  node overleaf-sync/ol-sync.mjs fetch --dir <path> [--project-id <id>] [--base-url ...] [--debug] [--json]
  node overleaf-sync/ol-sync.mjs apply --dir <path> [--project-id <id>] [--base-url ...] [--batch <batchId>]
  node overleaf-sync/ol-sync.mjs push --dir <path> [--project-id <id>] [--base-url ...] [--mongo-container mongo] [--concurrency 4] [--dry-run]
  node overleaf-sync/ol-sync.mjs watch --dir <path> [--project-id <id>] [--base-url ...] [--mongo-container mongo] [--dry-run]

Notes:
  - "link" writes ${CONFIG_FILENAME} into the target directory (no passwords stored).
  - "watch" reads ${CONFIG_FILENAME} if present; otherwise requires --project-id.
  - Session cookies are cached by default to avoid repeated logins. Disable via --no-session-cache.
    Default session cache path: ${DEFAULT_SESSION_PATH}
`
  process.stdout.write(text.trimStart() + '\n')
  process.exit(exitCode)
}

function parseArgs(argv) {
  const [, , command, ...rest] = argv
  const opts = {}
  const positional = []
  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i]
    if (!arg.startsWith('--')) {
      positional.push(arg)
      continue
    }
    const key = arg.slice(2)
    const next = rest[i + 1]
    if (next == null || next.startsWith('--')) {
      opts[key] = true
    } else {
      opts[key] = next
      i++
    }
  }
  return { command, opts, positional }
}

function debugLog(enabled, message) {
  if (!enabled) return
  process.stderr.write(`[debug] ${message}\\n`)
}

function fromPosix(relPath) {
  return String(relPath || '').split('/').join(path.sep)
}

function safePathComponent(value) {
  return String(value || '')
    .replace(/^https?:\/\//i, '')
    .replace(/[^a-zA-Z0-9._-]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 120) || 'overleaf'
}

function inboxProjectDir(baseUrl, projectId) {
  let host = ''
  try {
    host = new URL(baseUrl).host
  } catch {
    host = baseUrl
  }
  return path.join(DEFAULT_INBOX_ROOT, safePathComponent(host), String(projectId))
}

function backupProjectDir(baseUrl, projectId) {
  let host = ''
  try {
    host = new URL(baseUrl).host
  } catch {
    host = baseUrl
  }
  return path.join(DEFAULT_BACKUP_ROOT, safePathComponent(host), String(projectId))
}

function newBatchId() {
  return new Date().toISOString().replace(/[:.]/g, '-')
}

function mustString(opts, key) {
  const value = opts[key]
  if (!value || typeof value !== 'string') {
    throw new Error(`Missing required option: --${key}`)
  }
  return value
}

async function* walkFiles(rootDir) {
  const entries = await readdir(rootDir, { withFileTypes: true })
  for (const entry of entries) {
    const abs = path.join(rootDir, entry.name)
    const rel = path.relative(rootDir, abs)
    if (shouldIgnore(rel, entry.isDirectory())) continue
    if (entry.isDirectory()) {
      yield* walkFiles(abs)
    } else if (entry.isFile()) {
      yield abs
    }
  }
}

async function readText(url, jar, extraHeaders) {
  const headers = new Headers(extraHeaders || {})
  const cookie = jar?.headerValue?.() || ''
  if (cookie) headers.set('cookie', cookie)
  const res = await fetch(url, { headers })
  jar?.addFromSetCookie?.(res.headers.getSetCookie?.() || [])
  const body = await res.text()
  return { res, body }
}

async function readJson(url, jar, extraHeaders) {
  const headers = new Headers(extraHeaders || {})
  headers.set('accept', 'application/json')
  const cookie = jar?.headerValue?.() || ''
  if (cookie) headers.set('cookie', cookie)
  const res = await fetch(url, { headers })
  jar?.addFromSetCookie?.(res.headers.getSetCookie?.() || [])
  const bodyText = await res.text()
  let body
  try {
    body = bodyText ? JSON.parse(bodyText) : null
  } catch {
    body = null
  }
  return { res, body, bodyText }
}

async function postForm(url, jar, form, extraHeaders) {
  const headers = new Headers(extraHeaders || {})
  headers.set('accept', 'application/json')
  headers.set('content-type', 'application/x-www-form-urlencoded')
  const cookie = jar?.headerValue?.() || ''
  if (cookie) headers.set('cookie', cookie)
  const res = await fetch(url, {
    method: 'POST',
    headers,
    body: new URLSearchParams(form).toString(),
  })
  jar?.addFromSetCookie?.(res.headers.getSetCookie?.() || [])
  const bodyText = await res.text()
  let body
  try {
    body = bodyText ? JSON.parse(bodyText) : null
  } catch {
    body = null
  }
  return { res, body, bodyText }
}

async function postJson(url, headersInit, jsonBody) {
  const headers = new Headers(headersInit || {})
  headers.set('accept', 'application/json')
  headers.set('content-type', 'application/json')
  const res = await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify(jsonBody),
  })
  const bodyText = await res.text()
  let body
  try {
    body = bodyText ? JSON.parse(bodyText) : null
  } catch {
    body = null
  }
  return { res, body, bodyText }
}

async function postJsonSession(url, session, jsonBody) {
  const headers = new Headers()
  headers.set('accept', 'application/json')
  headers.set('content-type', 'application/json')
  headers.set('x-csrf-token', session.csrfToken)
  const cookie = session.jar.headerValue()
  if (cookie) headers.set('cookie', cookie)

  const res = await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify(jsonBody),
  })
  session.jar.addFromSetCookie(res.headers.getSetCookie?.() || [])

  const bodyText = await res.text()
  let body
  try {
    body = bodyText ? JSON.parse(bodyText) : null
  } catch {
    body = null
  }
  return { res, body, bodyText }
}

async function promptLine(label) {
  if (!process.stdin.isTTY) {
    throw new Error('Cannot prompt for input: stdin is not a TTY.')
  }
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: true,
  })
  const answer = await new Promise(resolve => rl.question(label, resolve))
  rl.close()
  return String(answer || '').trim()
}

async function promptHidden(label) {
  if (!process.stdin.isTTY) {
    throw new Error('Cannot prompt for input: stdin is not a TTY.')
  }
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: true,
  })
  rl.stdoutMuted = false
  rl._writeToOutput = function (stringToWrite) {
    if (rl.stdoutMuted) {
      // Write a single mask char per keypress (best-effort).
      if (stringToWrite === '\\n' || stringToWrite === '\\r\\n') return
      rl.output.write('*')
      return
    }
    rl.output.write(stringToWrite)
  }
  const answer = await new Promise(resolve => {
    rl.question(label, resolve)
    rl.stdoutMuted = true
  })
  rl.stdoutMuted = false
  rl.output.write('\\n')
  rl.close()
  return String(answer || '').trim()
}

async function login(baseUrl, email, password) {
  const jar = new CookieJar()
  const { body: loginHtml } = await readText(`${baseUrl}/login`, jar)
  const csrf = extractCsrfTokenFromHtml(loginHtml)
  if (!csrf) {
    throw new Error('Could not find CSRF token on /login')
  }

  const { res, body, bodyText } = await postForm(
    `${baseUrl}/login`,
    jar,
    { email, password, _csrf: csrf },
    { 'x-csrf-token': csrf }
  )
  if (!res.ok) {
    throw new Error(`Login failed: HTTP ${res.status} ${bodyText}`)
  }
  if (!body || !body.redir) {
    const msg =
      body?.message?.text ||
      body?.message?.error ||
      bodyText ||
      'Unknown login error'
    throw new Error(`Login failed: ${msg}`)
  }
  return { jar, csrfToken: csrf }
}

async function getPersonalInfo(baseUrl, session) {
  const { res, body, bodyText } = await readJson(
    `${baseUrl}/user/personal_info`,
    session.jar
  )
  if (!res.ok || !body?.id) {
    throw new Error(
      `Failed to fetch /user/personal_info: HTTP ${res.status} ${bodyText}`
    )
  }
  return body
}

async function createProject(baseUrl, session, { projectName, template } = {}) {
  const payload = {}
  if (projectName) payload.projectName = String(projectName)
  if (template) payload.template = String(template)

  // Prefer JSON; fall back to form encoding if needed.
  const jsonAttempt = await postJsonSession(`${baseUrl}/project/new`, session, payload)
  if (jsonAttempt.res.ok && jsonAttempt.body?.project_id) {
    return jsonAttempt.body.project_id
  }

  const formAttempt = await postForm(
    `${baseUrl}/project/new`,
    session.jar,
    payload,
    { 'x-csrf-token': session.csrfToken }
  )
  if (formAttempt.res.ok && formAttempt.body?.project_id) {
    return formAttempt.body.project_id
  }

  const details =
    jsonAttempt.bodyText ||
    formAttempt.bodyText ||
    `HTTP ${jsonAttempt.res.status}`
  throw new Error(`Failed to create project: ${details}`.trim())
}

function normalizeProjectId(project) {
  if (!project || typeof project !== 'object') return null
  const raw = project.id ?? project._id
  if (raw == null) return null
  return String(raw)
}

function normalizeProject(project) {
  const id = normalizeProjectId(project)
  if (!id) return null
  const normalized = { ...project }
  if (!normalized.id) normalized.id = id
  if (!normalized._id) normalized._id = id
  if (normalized.archived == null) normalized.archived = false
  if (normalized.trashed == null) normalized.trashed = false
  return normalized
}

function mergeProject(existing, incoming) {
  if (!existing) return incoming
  if (!incoming) return existing
  const merged = { ...existing }
  for (const [key, value] of Object.entries(incoming)) {
    if (value !== undefined) merged[key] = value
  }
  merged.archived = Boolean(existing.archived || incoming.archived)
  merged.trashed = Boolean(existing.trashed || incoming.trashed)
  return merged
}

async function fetchProjectsPaged(
  baseUrl,
  session,
  { filters, sort, pageSize, debug, label }
) {
  const projects = []
  const seenIds = new Set()
  const size = pageSize || 500
  let lastId = undefined
  let totalSize = null
  let pageCount = 0
  let pageNumber = 0
  const maxPages = 200

  while (pageCount < maxPages) {
    const page = { size, number: pageNumber }
    if (lastId) page.lastId = lastId
    const { res, body, bodyText } = await postJsonSession(
      `${baseUrl}/api/project`,
      session,
      {
        filters: filters || {},
        sort: sort || { by: 'lastUpdated', order: 'desc' },
        page,
      }
    )
    if (!res.ok || !body?.projects) {
      throw new Error(`HTTP ${res.status} ${bodyText}`)
    }

    const batch = body.projects || []
    if (typeof body.totalSize === 'number') {
      totalSize = body.totalSize
    } else if (typeof body.total_size === 'number') {
      totalSize = body.total_size
    }

    pageCount += 1
    pageNumber += 1
    let added = 0
    for (const item of batch) {
      const normalized = normalizeProject(item)
      if (!normalized) continue
      if (seenIds.has(normalized.id)) continue
      seenIds.add(normalized.id)
      projects.push(normalized)
      added += 1
    }

    debugLog(
      debug,
      `projects via /api/project${label ? ` (${label})` : ''}: page=${pageCount} number=${pageNumber - 1} status=${res.status} returned=${batch.length} added=${added}${
        totalSize != null ? ` totalSize=${totalSize}` : ''
      }${lastId ? ` lastId=${lastId}` : ''}`
    )

    if (batch.length === 0) break
    const nextLastId = normalizeProjectId(batch[batch.length - 1])
    if (!nextLastId || nextLastId === lastId) break
    lastId = nextLastId
    if (totalSize != null && projects.length >= totalSize) break
    if (added === 0) break
  }

  if (pageCount >= maxPages) {
    debugLog(
      debug,
      `projects via /api/project${label ? ` (${label})` : ''}: stopped at maxPages=${maxPages}`
    )
  }

  return projects
}

async function listProjects(baseUrl, session, { activeOnly, debug } = {}) {
  const projectsById = new Map()
  const sort = { by: 'lastUpdated', order: 'desc' }

  const addProjects = (label, items) => {
    let added = 0
    let updated = 0
    for (const item of items || []) {
      const normalized = normalizeProject(item)
      if (!normalized) continue
      const existing = projectsById.get(normalized.id)
      if (!existing) {
        projectsById.set(normalized.id, normalized)
        added += 1
      } else {
        projectsById.set(normalized.id, mergeProject(existing, normalized))
        updated += 1
      }
    }
    debugLog(
      debug,
      `projects merge${label ? ` (${label})` : ''}: added=${added} updated=${updated} total=${projectsById.size}`
    )
  }

  const tryFetch = async (label, filters) => {
    try {
      addProjects(
        label,
        await fetchProjectsPaged(baseUrl, session, {
          filters,
          sort,
          pageSize: 500,
          debug,
          label,
        })
      )
      return true
    } catch (err) {
      debugLog(
        debug,
        `projects: /api/project ${label} failed (${String(err?.message || err)})`
      )
      return false
    }
  }

  const apiOk = await tryFetch('all', {})
  if (apiOk) {
    await tryFetch('shared', { sharedWithUser: true })
    if (!activeOnly) {
      await tryFetch('archived', { archived: true })
      await tryFetch('trashed', { trashed: true })
    }
  } else {
    debugLog(debug, 'projects: falling back to /user/projects')
    // Fallback for older instances: this endpoint excludes archived/trashed.
    const { res, body, bodyText } = await readJson(
      `${baseUrl}/user/projects`,
      session.jar
    )
    if (!res.ok || !body?.projects) {
      throw new Error(
        `Failed to fetch /user/projects: HTTP ${res.status} ${bodyText}`
      )
    }
    debugLog(
      debug,
      `projects via /user/projects: status=${res.status} returned=${body.projects.length}`
    )
    addProjects('user-projects', body.projects)
  }

  let projects = Array.from(projectsById.values())
  if (activeOnly) {
    projects = projects.filter(p => !p.archived && !p.trashed)
  }
  return projects
}

async function detectWebApiCredentials(containerName) {
  try {
    // On some Overleaf images, secrets are stored under /etc/container_environment/
    // and not exported as process env vars.
    const { stdout } = await execFileAsync('docker', [
      'exec',
      containerName,
      'sh',
      '-lc',
      [
        'if [ -n "${WEB_API_USER:-}" ]; then echo "WEB_API_USER=$WEB_API_USER";',
        'elif [ -f /etc/container_environment/WEB_API_USER ]; then echo "WEB_API_USER=$(cat /etc/container_environment/WEB_API_USER)"; fi;',
        'if [ -n "${WEB_API_PASSWORD:-}" ]; then echo "WEB_API_PASSWORD=$WEB_API_PASSWORD";',
        'elif [ -f /etc/container_environment/WEB_API_PASSWORD ]; then echo "WEB_API_PASSWORD=$(cat /etc/container_environment/WEB_API_PASSWORD)"; fi;',
      ].join(' '),
    ])
    const lines = stdout.split('\n').map(s => s.trim())
    const userLine = lines.find(l => l.startsWith('WEB_API_USER='))
    const passLine = lines.find(l => l.startsWith('WEB_API_PASSWORD='))
    const user = userLine ? userLine.split('=', 2)[1] : null
    const pass = passLine ? passLine.split('=', 2)[1] : null
    if (!user || !pass) {
      throw new Error('missing WEB_API_USER/WEB_API_PASSWORD in container env')
    }
    return { user, pass }
  } catch (err) {
    throw new Error(
      `Could not auto-detect WEB_API credentials via docker exec (${containerName}): ${err.message}`
    )
  }
}

async function getRootFolderIdViaMongo(mongoContainerName, projectId) {
  const container = mongoContainerName || DEFAULT_MONGO_CONTAINER
  const script = [
    `const p=db.projects.findOne({_id:ObjectId("${projectId}")},{rootFolder:1});`,
    `if(!p||!p.rootFolder||!p.rootFolder[0]||!p.rootFolder[0]._id){quit(2)}`,
    `print(p.rootFolder[0]._id.toHexString())`,
  ].join(' ')
  try {
    const { stdout } = await execFileAsync('docker', [
      'exec',
      container,
      'mongosh',
      'sharelatex',
      '--quiet',
      '--eval',
      script,
    ])
    const out = String(stdout || '').trim()
    if (!/^[a-f0-9]{24}$/i.test(out)) {
      throw new Error(`unexpected output: ${out}`)
    }
    return out
  } catch (err) {
    throw new Error(
      `Could not read root folder id from Mongo via docker exec (${container}): ${err.message}`
    )
  }
}

async function getRootFolderIdViaPrivateJoin(baseUrl, projectId, userId, creds) {
  const { res, body, bodyText } = await postJson(
    `${baseUrl}/project/${projectId}/join`,
    { authorization: basicAuthHeader(creds.user, creds.pass) },
    { userId }
  )
  if (!res.ok) {
    throw new Error(
      `Private join failed: HTTP ${res.status} ${bodyText || ''}`.trim()
    )
  }
  const rootFolderId = body?.project?.rootFolder?.[0]?._id
  if (!rootFolderId) {
    throw new Error('Private join did not return project.rootFolder[0]._id')
  }
  return rootFolderId
}

async function uploadOne({
  baseUrl,
  session,
  projectId,
  rootFolderId,
  absPath,
  relPath,
  dryRun,
}) {
  const name = path.basename(relPath)
  const relativePath = toPosix(relPath)
  if (dryRun) {
    process.stdout.write(`[dry-run] upload ${relativePath}\\n`)
    return
  }
  const fileBytes = await readFile(absPath)
  const form = new FormData()
  form.set('name', name)
  form.set('relativePath', relativePath)
  form.set('qqfile', new Blob([fileBytes]), name)

  const headers = new Headers()
  headers.set('accept', 'application/json')
  headers.set('x-csrf-token', session.csrfToken)
  const cookie = session.jar.headerValue()
  if (cookie) headers.set('cookie', cookie)

  const url = `${baseUrl}/project/${projectId}/upload?folder_id=${encodeURIComponent(
    rootFolderId
  )}`
  const res = await fetch(url, { method: 'POST', headers, body: form })
  session.jar.addFromSetCookie(res.headers.getSetCookie?.() || [])
  const bodyText = await res.text()
  let body
  try {
    body = bodyText ? JSON.parse(bodyText) : null
  } catch {
    body = null
  }
  if (!res.ok || !body?.success) {
    throw new Error(
      `Upload failed (${relativePath}): HTTP ${res.status} ${bodyText}`.trim()
    )
  }
}

async function loadConfig(dir) {
  const cfgPath = path.join(dir, CONFIG_FILENAME)
  try {
    const raw = await readFile(cfgPath, 'utf8')
    return { cfgPath, cfg: JSON.parse(raw) }
  } catch {
    return { cfgPath, cfg: null }
  }
}

async function writeConfig(dir, cfg) {
  const cfgPath = path.join(dir, CONFIG_FILENAME)
  await writeFile(cfgPath, JSON.stringify(cfg, null, 2) + '\n', 'utf8')
  return cfgPath
}

async function ensureEmptyDirectory(absDir) {
  try {
    const st = await stat(absDir)
    if (!st.isDirectory()) {
      throw new Error(`Target path exists and is not a directory: ${absDir}`)
    }
  } catch (err) {
    if (err?.code === 'ENOENT') {
      await mkdir(absDir, { recursive: true })
      return
    }
    throw err
  }

  const entries = await readdir(absDir)
  if (entries.length > 0) {
    throw new Error(
      `Refusing to pull into a non-empty directory (would overwrite local files): ${absDir}`
    )
  }
}

async function downloadProjectZip(baseUrl, session, projectId, zipPath) {
  const cookie = session.jar.headerValue()
  const headers = new Headers()
  headers.set('accept', 'application/zip,application/octet-stream')
  headers.set('x-csrf-token', session.csrfToken)
  if (cookie) headers.set('cookie', cookie)

  const candidates = [
    `${baseUrl}/project/${projectId}/download/zip`,
    `${baseUrl}/project/${projectId}/download`,
  ]

  /** @type {{url:string, status:number, bodyText?:string}|null} */
  let lastError = null
  for (const url of candidates) {
    const res = await fetch(url, { headers })
    session.jar.addFromSetCookie(res.headers.getSetCookie?.() || [])

    if (!res.ok) {
      if (res.status === 404) {
        lastError = { url, status: res.status }
        continue
      }
      const bodyText = await res.text().catch(() => '')
      throw new Error(`Download failed: HTTP ${res.status} ${url} ${bodyText}`.trim())
    }
    if (!res.body) throw new Error(`Download failed: empty response body (${url})`)
    await pipeline(Readable.fromWeb(res.body), createWriteStream(zipPath))
    return { url }
  }

  const msg = lastError
    ? `Download failed: no working endpoint (last tried: ${lastError.url} HTTP ${lastError.status})`
    : 'Download failed: no working endpoint.'
  throw new Error(msg)
}

async function unzipInto(zipPath, destDir) {
  try {
    await execFileAsync('unzip', ['-q', zipPath, '-d', destDir])
  } catch (err) {
    const stderr = String(err?.stderr || err?.message || err)
    throw new Error(`unzip failed: ${stderr}`)
  }
}

async function maybeFlattenSingleRootFolder(destDir, { keepZipName } = {}) {
  const entries = await readdir(destDir, { withFileTypes: true })
  const keep = new Set([
    CONFIG_FILENAME,
    String(keepZipName || ''),
    '__MACOSX',
  ].filter(Boolean))

  const visible = entries.filter(e => !keep.has(e.name))
  if (visible.length !== 1) return { flattened: false }
  const only = visible[0]
  if (!only.isDirectory()) return { flattened: false }

  const wrapperDir = path.join(destDir, only.name)
  const inner = await readdir(wrapperDir, { withFileTypes: true })
  for (const entry of inner) {
    await rename(path.join(wrapperDir, entry.name), path.join(destDir, entry.name))
  }
  return { flattened: true, wrapper: only.name }
}

async function sha256File(absPath) {
  const buf = await readFile(absPath)
  return createHash('sha256').update(buf).digest('hex')
}

async function buildIndex(absDir) {
  /** @type {Map<string, {hash:string}>} */
  const out = new Map()
  for await (const absPath of walkFiles(absDir)) {
    const rel = toPosix(path.relative(absDir, absPath))
    const hash = await sha256File(absPath)
    out.set(rel, { hash })
  }
  return out
}

function diffIndexes(localIndex, remoteIndex) {
  const added = []
  const modified = []
  const deleted = []

  for (const [p, r] of remoteIndex.entries()) {
    const l = localIndex.get(p)
    if (!l) {
      added.push(p)
      continue
    }
    if (l.hash !== r.hash) {
      modified.push({ path: p, localHash: l.hash, remoteHash: r.hash })
    }
  }
  for (const [p] of localIndex.entries()) {
    if (!remoteIndex.has(p)) deleted.push(p)
  }

  added.sort()
  modified.sort((a, b) => a.path.localeCompare(b.path))
  deleted.sort()
  return { added, modified, deleted }
}

async function cmdProjects({ baseUrl, activeOnly, debug, json, authOpts }) {
  const normalizedBaseUrl = normalizeBaseUrl(baseUrl)
  const { session, reusedSession, sessionPath } = await ensureAuthenticated(
    normalizedBaseUrl,
    authOpts,
    { requireUserInfo: true }
  )
  debugLog(
    debug,
    `auth: baseUrl=${normalizedBaseUrl} reusedSession=${reusedSession ? 'yes' : 'no'} sessionPath=${sessionPath}`
  )
  const projects = await listProjects(normalizedBaseUrl, session, {
    activeOnly,
    debug,
  })
  if (json) {
    const out = projects.map(p => {
      const id = p._id || p.id
      return {
        id,
        name: p.name,
        accessLevel: p.accessLevel,
        archived: Boolean(p.archived),
        trashed: Boolean(p.trashed),
        lastUpdated: p.lastUpdated,
        lastUpdatedBy: p.lastUpdatedBy?.email || p.lastUpdatedBy?.id || null,
      }
    })
    process.stdout.write(JSON.stringify(out) + '\n')
    return
  }
  for (const p of projects) {
    const id = p._id || p.id
    const flags = [
      p.accessLevel,
      p.archived ? 'archived' : null,
      p.trashed ? 'trashed' : null,
    ]
      .filter(Boolean)
      .join(', ')
    process.stdout.write(`${id}\\t${p.name}\\t(${flags})\\n`)
  }
}

async function cmdPull({ baseUrl, projectId, dir, mongoContainer, authOpts }) {
  const normalizedBaseUrl = normalizeBaseUrl(baseUrl)
  const absDir = path.resolve(dir)
  await ensureEmptyDirectory(absDir)

  const debug = Boolean(authOpts?.debug)
  const { session, me } = await ensureAuthenticated(normalizedBaseUrl, authOpts, {
    requireUserInfo: true,
  })

  const zipName = '.ol-sync.download.zip'
  const zipPath = path.join(absDir, zipName)
  const { url: downloadUrl } = await downloadProjectZip(normalizedBaseUrl, session, projectId, zipPath)
  debugLog(debug, `downloaded zip via ${downloadUrl}`)

  await unzipInto(zipPath, absDir)
  const flattened = await maybeFlattenSingleRootFolder(absDir, { keepZipName: zipName })
  if (flattened.flattened) {
    debugLog(debug, `flattened wrapper folder: ${flattened.wrapper}`)
  }

  let rootFolderId
  try {
    rootFolderId = await getRootFolderIdViaMongo(mongoContainer, projectId)
    debugLog(debug, `rootFolderId resolved via mongo: ${rootFolderId}`)
  } catch (err) {
    debugLog(debug, `rootFolderId mongo lookup failed (${String(err?.message || err)})`)
    const creds = await detectWebApiCredentials(DEFAULT_CONTAINER)
    rootFolderId = await getRootFolderIdViaPrivateJoin(
      normalizedBaseUrl,
      projectId,
      me.id,
      creds
    )
    debugLog(debug, `rootFolderId resolved via private join: ${rootFolderId}`)
  }

  const cfg = {
    baseUrl: normalizedBaseUrl,
    projectId,
    rootFolderId,
    mongoContainer: mongoContainer || DEFAULT_MONGO_CONTAINER,
    container: DEFAULT_CONTAINER,
    linkedAt: new Date().toISOString(),
    pulledAt: new Date().toISOString(),
  }
  const writtenCfgPath = await writeConfig(absDir, cfg)
  process.stdout.write(`Pulled ${projectId} -> ${absDir}\nWrote ${writtenCfgPath}\n`)
}

async function cmdFetch({ baseUrl, projectId, dir, debug, json, authOpts }) {
  const absDir = path.resolve(dir)
  const { cfg } = await loadConfig(absDir)
  const effectiveBaseUrl = normalizeBaseUrl(cfg?.baseUrl || baseUrl)
  const effectiveProjectId = cfg?.projectId || projectId

  if (!effectiveProjectId) {
    throw new Error(
      `Missing project id. Provide --project-id or run 'link'/'pull' to create ${CONFIG_FILENAME}.`
    )
  }

  const { session } = await ensureAuthenticated(effectiveBaseUrl, authOpts)

  const projectInboxDir = inboxProjectDir(effectiveBaseUrl, effectiveProjectId)
  const batchId = newBatchId()
  const batchDir = path.join(projectInboxDir, batchId)
  await mkdir(batchDir, { recursive: true })

  const zipName = '.ol-sync.remote.zip'
  const zipPath = path.join(batchDir, zipName)
  const { url: downloadUrl } = await downloadProjectZip(
    effectiveBaseUrl,
    session,
    effectiveProjectId,
    zipPath
  )
  debugLog(debug, `downloaded zip via ${downloadUrl}`)

  await unzipInto(zipPath, batchDir)
  const flattened = await maybeFlattenSingleRootFolder(batchDir, { keepZipName: zipName })
  if (flattened.flattened) {
    debugLog(debug, `flattened wrapper folder: ${flattened.wrapper}`)
  }

  const remoteIndex = await buildIndex(batchDir)
  const localIndex = await buildIndex(absDir)
  const changes = diffIndexes(localIndex, remoteIndex)

  const manifest = {
    version: 1,
    baseUrl: effectiveBaseUrl,
    projectId: effectiveProjectId,
    batchId,
    localDir: absDir,
    inboxDir: batchDir,
    createdAt: new Date().toISOString(),
    changes,
  }

  const manifestPath = path.join(batchDir, '.ol-sync.inbox.json')
  await writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n', 'utf8')

  if (json) {
    process.stdout.write(JSON.stringify(manifest) + '\n')
    return
  }

  process.stdout.write(
    `Fetched remote snapshot into ${batchDir}\nadded=${changes.added.length} modified=${changes.modified.length} deleted=${changes.deleted.length}\n`
  )
  process.stdout.write(`Manifest: ${manifestPath}\n`)
}

async function cmdApply({ baseUrl, projectId, dir, batch, authOpts }) {
  const absDir = path.resolve(dir)
  const { cfg } = await loadConfig(absDir)
  const effectiveBaseUrl = normalizeBaseUrl(cfg?.baseUrl || baseUrl)
  const effectiveProjectId = cfg?.projectId || projectId

  if (!effectiveProjectId) {
    throw new Error(
      `Missing project id. Provide --project-id or run 'link'/'pull' to create ${CONFIG_FILENAME}.`
    )
  }

  const projectInboxDir = inboxProjectDir(effectiveBaseUrl, effectiveProjectId)
  const entries = await readdir(projectInboxDir, { withFileTypes: true }).catch(() => [])
  const batches = entries.filter(e => e.isDirectory()).map(e => e.name).sort()
  if (batches.length === 0) {
    throw new Error(
      `No inbox batches found for project ${effectiveProjectId}. Run 'fetch' first.`
    )
  }
  const batchId = batch ? String(batch) : batches[batches.length - 1]
  const batchDir = path.join(projectInboxDir, batchId)
  const manifestPath = path.join(batchDir, '.ol-sync.inbox.json')
  const raw = await readFile(manifestPath, 'utf8')
  const manifest = JSON.parse(raw)
  const changes = manifest?.changes || { added: [], modified: [], deleted: [] }

  const backupRoot = path.join(backupProjectDir(effectiveBaseUrl, effectiveProjectId), batchId)
  await mkdir(backupRoot, { recursive: true })

  const files = [
    ...changes.added.map(p => ({ path: p, kind: 'add' })),
    ...changes.modified.map(e => ({ path: e.path, kind: 'modify' })),
  ]

  let applied = 0
  for (const file of files) {
    const rel = fromPosix(file.path)
    const src = path.join(batchDir, rel)
    const dst = path.join(absDir, rel)

    try {
      const st = await stat(dst)
      if (st.isFile()) {
        const backupPath = path.join(backupRoot, rel)
        await mkdir(path.dirname(backupPath), { recursive: true })
        await copyFile(dst, backupPath)
      }
    } catch {
      // dst doesn't exist; nothing to backup
    }

    await mkdir(path.dirname(dst), { recursive: true })
    await copyFile(src, dst)
    applied++
  }

  process.stdout.write(
    `Applied ${applied} file(s) (last-write-wins).\nBackup: ${backupRoot}\n`
  )
  if (changes.deleted?.length) {
    process.stdout.write(
      `Note: ${changes.deleted.length} file(s) missing on remote were NOT deleted locally.\n`
    )
  }
}

async function cmdLink({
  baseUrl,
  projectId,
  dir,
  container,
  mongoContainer,
  force,
  authOpts,
}) {
  const normalizedBaseUrl = normalizeBaseUrl(baseUrl)
  const { cfg: existingCfg, cfgPath: existingCfgPath } = await loadConfig(dir)
  if (existingCfg && !force) {
    throw new Error(
      `Refusing to overwrite existing ${existingCfgPath}. Re-run with --force if you really want to replace it.`
    )
  }
  const debug = Boolean(authOpts?.debug)
  const { session, me } = await ensureAuthenticated(normalizedBaseUrl, authOpts, {
    requireUserInfo: true,
  })

  let rootFolderId
  try {
    rootFolderId = await getRootFolderIdViaMongo(mongoContainer, projectId)
    debugLog(debug, `rootFolderId resolved via mongo: ${rootFolderId}`)
  } catch (err) {
    debugLog(debug, `rootFolderId mongo lookup failed (${String(err?.message || err)})`)
    const creds = await detectWebApiCredentials(container)
    rootFolderId = await getRootFolderIdViaPrivateJoin(
      normalizedBaseUrl,
      projectId,
      me.id,
      creds
    )
    debugLog(debug, `rootFolderId resolved via private join: ${rootFolderId}`)
  }
  const cfg = {
    baseUrl: normalizedBaseUrl,
    projectId,
    rootFolderId,
    mongoContainer,
    container,
    linkedAt: new Date().toISOString(),
  }
  const writtenCfgPath = await writeConfig(dir, cfg)
  process.stdout.write(`Wrote ${writtenCfgPath}\\n`)
}

async function cmdCreate({ baseUrl, dir, name, mongoContainer, force, authOpts }) {
  const normalizedBaseUrl = normalizeBaseUrl(baseUrl)
  const absDir = path.resolve(dir)
  const { cfg: existingCfg, cfgPath: existingCfgPath } = await loadConfig(absDir)
  if (existingCfg && !force) {
    throw new Error(
      `Refusing to overwrite existing ${existingCfgPath}. Re-run with --force if you really want to replace it.`
    )
  }

  const projectName = String(name || path.basename(absDir) || 'Untitled').trim()
  if (!projectName) throw new Error('Project name cannot be empty.')

  const { session } = await ensureAuthenticated(normalizedBaseUrl, authOpts)
  const projectId = await createProject(normalizedBaseUrl, session, {
    projectName,
  })

  let rootFolderId = null
  const maxAttempts = 10
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      rootFolderId = await getRootFolderIdViaMongo(mongoContainer, projectId)
      break
    } catch (err) {
      if (attempt === maxAttempts) throw err
      await new Promise(resolve => setTimeout(resolve, 200))
    }
  }

  const cfg = {
    baseUrl: normalizedBaseUrl,
    projectId,
    rootFolderId,
    mongoContainer: mongoContainer || DEFAULT_MONGO_CONTAINER,
    container: DEFAULT_CONTAINER,
    linkedAt: new Date().toISOString(),
    createdAt: new Date().toISOString(),
  }
  const writtenCfgPath = await writeConfig(absDir, cfg)
  process.stdout.write(`Created ${projectId}\\nWrote ${writtenCfgPath}\\n`)
}

async function cmdPush({
  baseUrl,
  projectId,
  dir,
  dryRun,
  container,
  mongoContainer,
  concurrency,
  authOpts,
}) {
  const absDir = path.resolve(dir)
  const { cfg } = await loadConfig(absDir)
  const effectiveBaseUrl = normalizeBaseUrl(cfg?.baseUrl || baseUrl)
  const effectiveProjectId = cfg?.projectId || projectId
  const effectiveRootFolderId = cfg?.rootFolderId
  const effectiveContainer = cfg?.container || container
  const effectiveMongoContainer = cfg?.mongoContainer || mongoContainer

  if (!effectiveProjectId) {
    throw new Error(
      `Missing project id. Provide --project-id or run 'link' to create ${CONFIG_FILENAME}.`
    )
  }

  const debug = Boolean(authOpts?.debug)
  const { session, me } = await ensureAuthenticated(effectiveBaseUrl, authOpts, {
    requireUserInfo: !effectiveRootFolderId,
  })

  let rootFolderId = effectiveRootFolderId
  if (!rootFolderId) {
    try {
      rootFolderId = await getRootFolderIdViaMongo(
        effectiveMongoContainer,
        effectiveProjectId
      )
      debugLog(debug, `rootFolderId resolved via mongo: ${rootFolderId}`)
    } catch (err) {
      debugLog(debug, `rootFolderId mongo lookup failed (${String(err?.message || err)})`)
      const creds = await detectWebApiCredentials(effectiveContainer)
      rootFolderId = await getRootFolderIdViaPrivateJoin(
        effectiveBaseUrl,
        effectiveProjectId,
        me.id,
        creds
      )
      debugLog(debug, `rootFolderId resolved via private join: ${rootFolderId}`)
    }
  }

  const tasks = []
  for await (const absPath of walkFiles(absDir)) {
    tasks.push({
      absPath,
      relPath: path.relative(absDir, absPath),
    })
  }

  const poolSize = Math.max(1, Number.parseInt(String(concurrency || ''), 10) || 4)
  let ok = 0
  let failed = 0
  let nextIndex = 0

  const worker = async () => {
    while (true) {
      const idx = nextIndex
      nextIndex += 1
      if (idx >= tasks.length) return
      const task = tasks[idx]
      try {
        await uploadOne({
          baseUrl: effectiveBaseUrl,
          session,
          projectId: effectiveProjectId,
          rootFolderId,
          absPath: task.absPath,
          relPath: task.relPath,
          dryRun,
        })
        ok += 1
      } catch (err) {
        failed += 1
        process.stderr.write(String(err.message || err) + '\\n')
      }
    }
  }

  await Promise.all(Array.from({ length: Math.min(poolSize, tasks.length || 1) }, worker))
  process.stdout.write(`Done. uploaded=${ok} failed=${failed}\\n`)
}

async function cmdWatch({
  baseUrl,
  projectId,
  dir,
  dryRun,
  container,
  mongoContainer,
  authOpts,
}) {
  const absDir = path.resolve(dir)
  const { cfg } = await loadConfig(absDir)
  const effectiveBaseUrl = normalizeBaseUrl(cfg?.baseUrl || baseUrl)
  const effectiveProjectId = cfg?.projectId || projectId
  const effectiveRootFolderId = cfg?.rootFolderId
  const effectiveContainer = cfg?.container || container
  const effectiveMongoContainer = cfg?.mongoContainer || mongoContainer

  if (!effectiveProjectId) {
    throw new Error(
      `Missing project id. Provide --project-id or run 'link' to create ${CONFIG_FILENAME}.`
    )
  }

  const debug = Boolean(authOpts?.debug)
  const { session, me } = await ensureAuthenticated(effectiveBaseUrl, authOpts, {
    requireUserInfo: !effectiveRootFolderId,
  })

  let rootFolderId = effectiveRootFolderId
  if (!rootFolderId) {
    try {
      rootFolderId = await getRootFolderIdViaMongo(
        effectiveMongoContainer,
        effectiveProjectId
      )
      debugLog(debug, `rootFolderId resolved via mongo: ${rootFolderId}`)
    } catch (err) {
      debugLog(debug, `rootFolderId mongo lookup failed (${String(err?.message || err)})`)
      const creds = await detectWebApiCredentials(effectiveContainer)
      rootFolderId = await getRootFolderIdViaPrivateJoin(
        effectiveBaseUrl,
        effectiveProjectId,
        me.id,
        creds
      )
      debugLog(debug, `rootFolderId resolved via private join: ${rootFolderId}`)
    }
  }

  process.stdout.write(
    `Watching ${absDir}\\n→ ${effectiveBaseUrl} project=${effectiveProjectId}\\n`
  )

  /** @type {Map<string, NodeJS.Timeout>} */
  const debounce = new Map()
  let queue = Promise.resolve()

  const scheduleUpload = relPath => {
    if (shouldIgnore(relPath, false)) return
    clearTimeout(debounce.get(relPath))
    debounce.set(
      relPath,
      setTimeout(() => {
        debounce.delete(relPath)
        const absPath = path.join(absDir, relPath)
        queue = queue
          .then(async () => {
            let st
            try {
              st = await stat(absPath)
            } catch {
              // removed; ignore for now (no remote delete by default)
              return
            }
            if (!st.isFile()) return
            await uploadOne({
              baseUrl: effectiveBaseUrl,
              session,
              projectId: effectiveProjectId,
              rootFolderId,
              absPath,
              relPath,
              dryRun,
            })
            process.stdout.write(`synced ${toPosix(relPath)}\\n`)
          })
          .catch(err => {
            process.stderr.write(String(err.message || err) + '\\n')
          })
      }, 250)
    )
  }

  const watcher = (await import('node:fs')).watch(absDir, { recursive: true })
  watcher.on('change', (_eventType, filename) => {
    if (!filename) return
    scheduleUpload(filename)
  })
  watcher.on('error', err => {
    process.stderr.write(`watch error: ${String(err.message || err)}\\n`)
  })

  await new Promise(() => {})
}

async function main() {
  const { command, opts } = parseArgs(process.argv)
  if (command === '--help' || command === '-h') usage(0)
  if (!command || opts.help || opts.h) usage(0)

  try {
    if (command === 'projects') {
      await cmdProjects({
        baseUrl: opts['base-url'] || DEFAULT_BASE_URL,
        activeOnly: Boolean(opts['active-only']),
        debug: Boolean(opts.debug),
        json: Boolean(opts.json),
        authOpts: opts,
      })
      return
    }
    if (command === 'link') {
      await cmdLink({
        baseUrl: opts['base-url'] || DEFAULT_BASE_URL,
        projectId: mustString(opts, 'project-id'),
        dir: path.resolve(opts.dir || '.'),
        mongoContainer: opts['mongo-container'] || DEFAULT_MONGO_CONTAINER,
        container: opts.container || DEFAULT_CONTAINER,
        force: Boolean(opts.force),
        authOpts: opts,
      })
      return
    }
    if (command === 'create') {
      await cmdCreate({
        baseUrl: opts['base-url'] || DEFAULT_BASE_URL,
        dir: path.resolve(mustString(opts, 'dir')),
        name: opts.name,
        mongoContainer: opts['mongo-container'] || DEFAULT_MONGO_CONTAINER,
        force: Boolean(opts.force),
        authOpts: opts,
      })
      return
    }
    if (command === 'pull') {
      await cmdPull({
        baseUrl: opts['base-url'] || DEFAULT_BASE_URL,
        projectId: mustString(opts, 'project-id'),
        dir: path.resolve(mustString(opts, 'dir')),
        mongoContainer: opts['mongo-container'] || DEFAULT_MONGO_CONTAINER,
        authOpts: opts,
      })
      return
    }
    if (command === 'fetch') {
      await cmdFetch({
        baseUrl: opts['base-url'] || DEFAULT_BASE_URL,
        projectId: opts['project-id'],
        dir: path.resolve(opts.dir || '.'),
        debug: Boolean(opts.debug),
        json: Boolean(opts.json),
        authOpts: opts,
      })
      return
    }
    if (command === 'apply') {
      await cmdApply({
        baseUrl: opts['base-url'] || DEFAULT_BASE_URL,
        projectId: opts['project-id'],
        dir: path.resolve(opts.dir || '.'),
        batch: opts.batch,
        authOpts: opts,
      })
      return
    }
    if (command === 'push') {
      await cmdPush({
        baseUrl: opts['base-url'] || DEFAULT_BASE_URL,
        projectId: opts['project-id'],
        dir: path.resolve(opts.dir || '.'),
        dryRun: Boolean(opts['dry-run']),
        container: opts.container || DEFAULT_CONTAINER,
        mongoContainer: opts['mongo-container'] || DEFAULT_MONGO_CONTAINER,
        concurrency: opts.concurrency,
        authOpts: opts,
      })
      return
    }
    if (command === 'watch') {
      await cmdWatch({
        baseUrl: opts['base-url'] || DEFAULT_BASE_URL,
        projectId: opts['project-id'],
        dir: path.resolve(opts.dir || '.'),
        dryRun: Boolean(opts['dry-run']),
        container: opts.container || DEFAULT_CONTAINER,
        mongoContainer: opts['mongo-container'] || DEFAULT_MONGO_CONTAINER,
        authOpts: opts,
      })
      return
    }
    usage(1)
  } catch (err) {
    process.stderr.write(String(err.message || err) + '\\n')
    process.exit(1)
  }
}

main()
