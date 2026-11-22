#!/usr/bin/env bash
set -euo pipefail

CAPTURE_URL="${CAPTURE_URL:?Set CAPTURE_URL to the exact preview URL}"
CAPTURE_DIR="${CAPTURE_DIR:?Set CAPTURE_DIR to the evidence output directory}"
export CAPTURE_URL CAPTURE_DIR

/usr/bin/time -p mkdir -p "$CAPTURE_DIR"
/usr/bin/time -p node --input-type=module <<'NODE'
import { createRequire } from 'node:module'
import { mkdirSync } from 'node:fs'
import { join } from 'node:path'

const output = process.env.CAPTURE_DIR
const url = process.env.CAPTURE_URL
const fail = (message, code = 1) => { const error = new Error(message); error.exitCode = code; throw error }
let browser
let exitCode = 0
try {
  let parsed
  try { parsed = new URL(url) } catch { fail(`Invalid CAPTURE_URL: ${url}`) }
  if (!['http:', 'https:'].includes(parsed.protocol)) fail('CAPTURE_URL must use HTTP or HTTPS.')
  mkdirSync(output, { recursive: true })

  const runtime = join(process.env.HOME, '.local/share/omgithub-playwright')
  let chromium, config
  try {
    const require = createRequire(join(runtime, 'package.json'))
    chromium = require('playwright').chromium
    config = (await import('node:fs')).readFileSync(join(runtime, process.platform === 'darwin' ? 'metal.json' : 'linux.json'), 'utf8')
    config = JSON.parse(config)
    if (process.platform === 'linux') process.env.DISPLAY ||= ':' + (await import('node:fs')).readFileSync(join(runtime, 'display'), 'utf8').trim()
  } catch (error) {
    fail(`Browser setup unavailable: ${error.message}`, 75)
  }
  try { browser = await chromium.launch({ ...config.browser.launchOptions, timeout: 30000 }) }
  catch (error) { fail(`Could not launch capture browser: ${error.message}`, 75) }

  for (const [name, width, height] of [['desktop', 1280, 800], ['mobile', 390, 844]]) {
    let page
    try { page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1, isMobile: name === 'mobile', hasTouch: name === 'mobile' }) }
    catch (error) { fail(`Could not create ${name} browser view: ${error.message}`, 75) }
    page.setDefaultTimeout(25000)
    const pageErrors = []
    page.on('pageerror', error => pageErrors.push(error.message))
    let response
    try { response = await page.goto(url, { waitUntil: 'load', timeout: 45000 }) }
    catch (error) {
      await page.close().catch(() => {})
      fail(`Temporary navigation/browser failure at ${url}: ${error.message}`, 75)
    }
    if (!response) { await page.close(); fail(`No document response from ${url}`, 75) }
    if (!response.ok()) {
      const status = response.status()
      await page.close()
      fail(`Preview returned HTTP ${status}: ${url}`, [408, 429, 500, 502, 503, 504].includes(status) ? 75 : 1)
    }
    try {
      await page.waitForFunction(() => {
        const body = document.body
        const canvas = document.querySelector('canvas')
        const start = document.querySelector('#startBtn')
        return document.readyState === 'complete' && body && getComputedStyle(body).visibility !== 'hidden' && getComputedStyle(body).display !== 'none' && canvas?.getBoundingClientRect().width > 0 && start?.getClientRects().length > 0
      }, { timeout: 20000 })
      await page.waitForFunction(() => document.fonts.status === 'loaded', { timeout: 10000 })
    } catch (error) {
      await page.close().catch(() => {})
      fail(`Rendered game content was not ready in the ${name} view: ${error.message}`)
    }
    if (pageErrors.length) {
      await page.close()
      fail(`Game JavaScript error in ${name} view: ${pageErrors.join('; ')}`)
    }
    try { await page.screenshot({ path: join(output, `final-${name}.png`), fullPage: false, timeout: 30000 }) }
    catch (error) {
      await page.close().catch(() => {})
      fail(`Could not save ${name} screenshot: ${error.message}`, browser.isConnected() ? 1 : 75)
    }
    await page.close()
    console.log(`Captured ${name} view from ${url}`)
  }
} catch (error) {
  console.error(error)
  exitCode = error.exitCode || 1
} finally {
  try { await browser?.close() } catch (error) { console.error(`Browser close failed: ${error.message}`); exitCode ||= 75 }
}
process.exitCode = exitCode
NODE
