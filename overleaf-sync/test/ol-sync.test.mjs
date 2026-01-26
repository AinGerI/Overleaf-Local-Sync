import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

import path from 'node:path'

import {
  CookieJar,
  CONFIG_FILENAME,
  DEFAULT_IGNORE_DIRS,
  DEFAULT_IGNORE_FILES,
  basicAuthHeader,
  extractCsrfToken,
  shouldIgnore,
  toPosix,
} from '../lib.mjs'

// Minimal regression tests for parsing helpers used by overleaf-sync/ol-sync.mjs

test('extract CSRF token from login html fixture', async () => {
  const html = await readFile(new URL('./fixtures/login.html', import.meta.url), 'utf8')
  const token = extractCsrfToken(html)
  assert.equal(token, 'csrf-token-value')
})

test('CookieJar stores first part of Set-Cookie', () => {
  const jar = new CookieJar()
  jar.addFromSetCookie([
    'overleaf.sid=s%3Aabc123; Path=/; HttpOnly; SameSite=Lax',
    'other=value; Path=/',
  ])
  const header = jar.headerValue()
  assert.match(header, /overleaf\.sid=s%3Aabc123/)
  assert.match(header, /other=value/)
})

test('CookieJar ignores malformed Set-Cookie values', () => {
  const jar = new CookieJar()
  jar.addFromSetCookie(['', 'noequals', '=novalue', ' spaced = value ; Path=/'])
  const header = jar.headerValue()
  assert.match(header, /spaced=value/)
  assert.ok(!header.includes('noequals'))
})

test('CookieJar toObject/fromObject roundtrip', () => {
  const jar = CookieJar.fromObject({ a: '1', b: '2' })
  assert.deepEqual(jar.toObject(), { a: '1', b: '2' })
  const header = jar.headerValue()
  assert.match(header, /a=1/)
  assert.match(header, /b=2/)
})

test('extract CSRF token from _csrf input', () => {
  const html = '<form><input name="_csrf" value="csrf-input-value"></form>'
  const token = extractCsrfToken(html)
  assert.equal(token, 'csrf-input-value')
})

test('toPosix normalizes platform separator', () => {
  const rel = ['a', 'b', 'c'].join(path.sep)
  assert.equal(toPosix(rel), 'a/b/c')
})

test('shouldIgnore handles empty, files, and directories', () => {
  assert.equal(shouldIgnore('', false), true)
  assert.equal(shouldIgnore(`.git${path.sep}config`, false), true)
  assert.equal(shouldIgnore(`node_modules${path.sep}lib.js`, false), true)
  assert.equal(shouldIgnore(`src${path.sep}.idea`, true), true)
  assert.equal(shouldIgnore(`__MACOSX${path.sep}x`, true), true)
  assert.equal(shouldIgnore(`.ol-sync.download.zip`, false), true)
  assert.equal(shouldIgnore(`src${path.sep}main.tex`, false), false)
})

test('shouldIgnore respects default ignore lists', () => {
  for (const dir of DEFAULT_IGNORE_DIRS) {
    assert.equal(shouldIgnore(`${dir}${path.sep}x`, false), true)
  }
  for (const file of DEFAULT_IGNORE_FILES) {
    assert.equal(shouldIgnore(file, false), true)
  }
  assert.equal(shouldIgnore(CONFIG_FILENAME, false), true)
})

test('basicAuthHeader encodes credentials', () => {
  const header = basicAuthHeader('user', 'pass')
  assert.equal(header, 'Basic dXNlcjpwYXNz')
})
