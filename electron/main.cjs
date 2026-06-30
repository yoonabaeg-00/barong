const { app, BrowserWindow, ipcMain, safeStorage, screen, shell } = require('electron')
const { execFile } = require('node:child_process')
const { google } = require('googleapis')
const fs = require('node:fs')
const http = require('node:http')
const path = require('node:path')
const url = require('node:url')

const TOKEN_FILE = 'google-calendar-token.bin'
const CALENDAR_STATE_FILE = 'google-calendar-state.json'
const SCOPES = ['https://www.googleapis.com/auth/calendar.events.readonly']

let mainWindow

const WINDOW_SIZES = {
  collapsed: { width: 232, height: 58 },
  expanded: { width: 560, height: 318 },
}

function getWindowPosition(size) {
  const display = screen.getPrimaryDisplay()
  const { width, x, y } = display.bounds

  return {
    x: Math.round(x + width / 2 - size.width / 2),
    y: y,
    width: size.width,
    height: size.height,
  }
}

function loadLocalEnv() {
  for (const filename of ['.env.local', '.env']) {
    const envPath = path.join(app.getAppPath(), filename)
    if (!fs.existsSync(envPath)) continue

    const content = fs.readFileSync(envPath, 'utf8')
    for (const line of content.split('\n')) {
      const trimmed = line.trim()
      if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue
      const [key, ...valueParts] = trimmed.split('=')
      if (!process.env[key]) {
        process.env[key] = valueParts.join('=').replace(/^["']|["']$/g, '')
      }
    }
  }
}

function getGoogleConfig() {
  return {
    clientId: process.env.GOOGLE_CLIENT_ID || process.env.VITE_GOOGLE_CLIENT_ID || '',
    clientSecret:
      process.env.GOOGLE_CLIENT_SECRET || process.env.VITE_GOOGLE_CLIENT_SECRET || '',
  }
}

function getApplicationDefaultCredentialsPath() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    return process.env.GOOGLE_APPLICATION_CREDENTIALS
  }
  return path.join(app.getPath('home'), '.config', 'gcloud', 'application_default_credentials.json')
}

function readApplicationDefaultCredentials() {
  const credentialsPath = getApplicationDefaultCredentialsPath()
  if (!fs.existsSync(credentialsPath)) return null

  try {
    const credentials = JSON.parse(fs.readFileSync(credentialsPath, 'utf8'))
    if (
      credentials.type !== 'authorized_user' ||
      !credentials.client_id ||
      !credentials.client_secret ||
      !credentials.refresh_token
    ) {
      return null
    }
    return credentials
  } catch {
    return null
  }
}

function findGcloudCommand() {
  const candidates = [
    '/opt/homebrew/bin/gcloud',
    '/usr/local/bin/gcloud',
    path.join(app.getPath('home'), 'google-cloud-sdk', 'bin', 'gcloud'),
  ]
  return candidates.find((candidate) => fs.existsSync(candidate)) || ''
}

function getTokenPath() {
  return path.join(app.getPath('userData'), TOKEN_FILE)
}

function getCalendarStatePaths() {
  const appData = app.getPath('appData')
  return [
    path.join(app.getPath('userData'), CALENDAR_STATE_FILE),
    path.join(appData, 'barong', CALENDAR_STATE_FILE),
    path.join(appData, '바롱이', CALENDAR_STATE_FILE),
  ]
}

function writeCalendarState(state) {
  const payload = JSON.stringify(
    {
      connected: false,
      events: [],
      updatedAt: new Date().toISOString(),
      ...state,
    },
    null,
    2,
  )

  for (const statePath of getCalendarStatePaths()) {
    fs.mkdirSync(path.dirname(statePath), { recursive: true })
    fs.writeFileSync(statePath, payload)
  }
}

function saveTokens(tokens) {
  const tokenPath = getTokenPath()
  const raw = Buffer.from(JSON.stringify(tokens), 'utf8')
  const encrypted = safeStorage.isEncryptionAvailable()
    ? safeStorage.encryptString(raw.toString('utf8'))
    : raw
  fs.writeFileSync(tokenPath, encrypted)
}

function readTokens() {
  const tokenPath = getTokenPath()
  if (!fs.existsSync(tokenPath)) return null

  const stored = fs.readFileSync(tokenPath)
  if (safeStorage.isEncryptionAvailable()) {
    return JSON.parse(safeStorage.decryptString(stored))
  }
  return JSON.parse(stored.toString('utf8'))
}

function removeTokens() {
  const tokenPath = getTokenPath()
  if (fs.existsSync(tokenPath)) fs.rmSync(tokenPath)
  writeCalendarState({ connected: false, events: [] })
}

function createOAuthClient(redirectUri, overrideConfig = null) {
  const { clientId, clientSecret } = overrideConfig || getGoogleConfig()
  if (!clientId) {
    throw new Error(
      'Google Calendar 연결 준비가 아직 안 됐어. Google 로그인을 먼저 진행해줘.',
    )
  }

  return new google.auth.OAuth2(clientId, clientSecret, redirectUri)
}

function createOAuthCallbackServer() {
  return new Promise((resolve, reject) => {
    const server = http.createServer()

    server.on('request', (request, response) => {
      const requestUrl = new url.URL(request.url || '/', `http://${request.headers.host}`)

      if (requestUrl.pathname !== '/oauth2callback') {
        response.writeHead(404)
        response.end('Not found')
        return
      }

      const code = requestUrl.searchParams.get('code')
      const error = requestUrl.searchParams.get('error')

      response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
      response.end(`
        <html>
          <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 32px;">
            <h2>바롱이 캘린더 연결</h2>
            <p>${code ? '연결됐어요. 이 창은 닫아도 돼요.' : '연결이 완료되지 않았어요.'}</p>
          </body>
        </html>
      `)

      if (error) {
        server.emit('oauth-error', new Error(error))
      } else {
        server.emit('oauth-code', code)
      }
    })

    server.on('error', reject)
    server.listen(0, '127.0.0.1', () => {
      const address = server.address()
      if (!address || typeof address === 'string') {
        reject(new Error('Could not create local OAuth callback server.'))
        return
      }
      resolve({ server, port: address.port })
    })
  })
}

async function connectGoogleCalendar() {
  if (!getGoogleConfig().clientId) {
    return connectGoogleCalendarWithGcloud()
  }

  const { server, port } = await createOAuthCallbackServer()
  const redirectUri = `http://127.0.0.1:${port}/oauth2callback`
  const oauth2Client = createOAuthClient(redirectUri)

  const authUrl = oauth2Client.generateAuthUrl({
    access_type: 'offline',
    prompt: 'consent',
    scope: SCOPES,
  })

  const codePromise = new Promise((resolve, reject) => {
    server.once('oauth-code', resolve)
    server.once('oauth-error', reject)
    setTimeout(() => reject(new Error('Google Calendar connection timed out.')), 120000)
  })

  await shell.openExternal(authUrl)
  try {
    const code = await codePromise
    const { tokens } = await oauth2Client.getToken(code)
    saveTokens(tokens)
    writeCalendarState({ connected: true, events: [] })
    return { connected: true }
  } finally {
    server.close()
  }
}

function connectGoogleCalendarWithGcloud() {
  const gcloud = findGcloudCommand()
  if (!gcloud) {
    throw new Error('Google 로그인 도구가 아직 없어. 먼저 Google Cloud SDK 설치가 필요해.')
  }

  return new Promise((resolve, reject) => {
    execFile(
      gcloud,
      [
        'auth',
        'application-default',
        'login',
        `--scopes=${SCOPES.join(',')}`,
      ],
      { timeout: 300000 },
      async (error) => {
        if (error) {
          reject(new Error('Google 로그인이 완료되지 않았어. 브라우저에서 허용까지 눌러줘.'))
          return
        }

        if (!readApplicationDefaultCredentials()) {
          reject(new Error('Google 로그인 토큰을 찾지 못했어. 한 번만 다시 시도해줘.'))
          return
        }

        writeCalendarState({ connected: true, events: [] })
        try {
          await listUpcomingEvents()
        } catch {
          // The UI will surface the next explicit calendar read error.
        }
        resolve({ connected: true })
      },
    )
  })
}

function getAuthedCalendarClient() {
  const tokens = readTokens()
  if (tokens) {
    const oauth2Client = createOAuthClient('http://127.0.0.1')
    oauth2Client.setCredentials(tokens)
    oauth2Client.on('tokens', (refreshedTokens) => {
      saveTokens({ ...tokens, ...refreshedTokens })
    })
    return google.calendar({ version: 'v3', auth: oauth2Client })
  }

  const applicationDefaultCredentials = readApplicationDefaultCredentials()
  if (!applicationDefaultCredentials) return null

  const oauth2Client = createOAuthClient('http://127.0.0.1', {
    clientId: applicationDefaultCredentials.client_id,
    clientSecret: applicationDefaultCredentials.client_secret,
  })
  oauth2Client.setCredentials({
    refresh_token: applicationDefaultCredentials.refresh_token,
  })
  return google.calendar({ version: 'v3', auth: oauth2Client })
}

async function listUpcomingEvents() {
  const calendar = getAuthedCalendarClient()
  if (!calendar) {
    const result = { connected: false, events: [] }
    writeCalendarState(result)
    return result
  }

  const now = new Date()
  const tomorrow = new Date(now)
  tomorrow.setDate(tomorrow.getDate() + 1)

  const response = await calendar.events.list({
    calendarId: 'primary',
    timeMin: now.toISOString(),
    timeMax: tomorrow.toISOString(),
    singleEvents: true,
    orderBy: 'startTime',
    maxResults: 10,
    showDeleted: false,
  })

  const events = (response.data.items || [])
    .filter((event) => {
      if (!event.start?.dateTime) return false
      if (event.status === 'cancelled') return false
      if (event.transparency === 'transparent') return false
      return !event.attendees?.some(
        (attendee) => attendee.self && attendee.responseStatus === 'declined',
      )
    })
    .map((event) => ({
      id: event.id,
      title: event.summary || '제목 없는 회의',
      start: event.start.dateTime,
      end: event.end?.dateTime || '',
      location: event.location || '',
      htmlLink: event.htmlLink || '',
      meetingLink:
        event.hangoutLink ||
        event.conferenceData?.entryPoints?.find((entryPoint) =>
          ['video', 'more'].includes(entryPoint.entryPointType),
        )?.uri ||
        '',
    }))

  const result = { connected: true, events }
  writeCalendarState(result)
  return result
}

function createMainWindow() {
  const collapsed = getWindowPosition(WINDOW_SIZES.collapsed)

  mainWindow = new BrowserWindow({
    width: collapsed.width,
    height: collapsed.height,
    x: collapsed.x,
    y: collapsed.y,
    frame: false,
    transparent: true,
    resizable: false,
    alwaysOnTop: true,
    skipTaskbar: false,
    title: '바롱이',
    trafficLightPosition: { x: 12, y: 12 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  })

  mainWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
  mainWindow.setAlwaysOnTop(true, 'screen-saver')

  if (process.env.VITE_DEV_SERVER_URL) {
    mainWindow.loadURL(`${process.env.VITE_DEV_SERVER_URL}?mode=app`)
  } else {
    mainWindow.loadFile(path.join(__dirname, '../dist/index.html'), {
      query: { mode: 'app' },
    })
  }
}

app.whenReady().then(() => {
  loadLocalEnv()
  createMainWindow()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createMainWindow()
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})

ipcMain.handle('calendar:get-status', () => ({
  connected: Boolean(readTokens() || readApplicationDefaultCredentials()),
  configured: Boolean(getGoogleConfig().clientId || findGcloudCommand()),
}))

ipcMain.handle('calendar:connect', async () => connectGoogleCalendar())
ipcMain.handle('calendar:list-events', async () => {
  try {
    return await listUpcomingEvents()
  } catch (error) {
    writeCalendarState({
      connected: Boolean(readTokens()),
      events: [],
      error: error instanceof Error ? error.message : 'Calendar sync failed.',
    })
    throw error
  }
})
ipcMain.handle('calendar:disconnect', () => {
  removeTokens()
  return { connected: false }
})

ipcMain.handle('app:open-external', (_event, targetUrl) => {
  if (typeof targetUrl === 'string' && targetUrl.startsWith('https://')) {
    shell.openExternal(targetUrl)
  }
})

ipcMain.handle('app:set-expanded', (_event, expanded) => {
  if (!mainWindow) return

  const size = expanded ? WINDOW_SIZES.expanded : WINDOW_SIZES.collapsed
  const next = getWindowPosition(size)
  mainWindow.setBounds(next, true)
})
