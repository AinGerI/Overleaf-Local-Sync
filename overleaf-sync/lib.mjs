import path from 'node:path'

export const DEFAULT_BASE_URL = 'http://localhost'
export const DEFAULT_CONTAINER = 'sharelatex'
export const CONFIG_FILENAME = '.ol-sync.json'

export const DEFAULT_IGNORE_DIRS = new Set([
  '.git',
  '.vscode',
  '.idea',
  'node_modules',
  '__pycache__',
  '__MACOSX',
])

export const DEFAULT_IGNORE_FILES = new Set(['.DS_Store', CONFIG_FILENAME])

export class CookieJar {
  /** @type {Map<string, string>} */
  #cookies = new Map()

  addFromSetCookie(headers) {
    for (const header of headers || []) {
      const firstPart = String(header).split(';', 1)[0] || ''
      const eq = firstPart.indexOf('=')
      if (eq <= 0) continue
      const name = firstPart.slice(0, eq).trim()
      const value = firstPart.slice(eq + 1).trim()
      if (!name) continue
      this.#cookies.set(name, value)
    }
  }

  set(name, value) {
    this.#cookies.set(String(name), String(value))
  }

  headerValue() {
    if (this.#cookies.size === 0) return ''
    return Array.from(this.#cookies.entries())
      .map(([k, v]) => `${k}=${v}`)
      .join('; ')
  }

  toObject() {
    return Object.fromEntries(this.#cookies.entries())
  }

  static fromObject(obj) {
    const jar = new CookieJar()
    for (const [name, value] of Object.entries(obj || {})) {
      jar.set(name, value)
    }
    return jar
  }
}

export function toPosix(relPath) {
  return relPath.split(path.sep).join('/')
}

export function shouldIgnore(relPath, isDir) {
  const parts = toPosix(relPath).split('/').filter(Boolean)
  if (parts.length === 0) return true
  const last = parts[parts.length - 1]
  if (last.startsWith('.ol-sync.')) return true
  if (!isDir && DEFAULT_IGNORE_FILES.has(last)) return true
  for (const part of parts) {
    if (DEFAULT_IGNORE_DIRS.has(part)) return true
  }
  return false
}

export function extractCsrfToken(html) {
  const metaMatch = html.match(
    /<meta\s+name="ol-csrfToken"\s+content="([^"]+)"/i
  )
  if (metaMatch) return metaMatch[1]
  const inputMatch = html.match(/<input\s+name="_csrf"[^>]*\svalue="([^"]+)"/i)
  if (inputMatch) return inputMatch[1]
  return null
}

export function basicAuthHeader(user, pass) {
  const token = Buffer.from(`${user}:${pass}`, 'utf8').toString('base64')
  return `Basic ${token}`
}
