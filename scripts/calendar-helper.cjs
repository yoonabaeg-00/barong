const { google } = require('googleapis')
const fs = require('node:fs')
const http = require('node:http')
const os = require('node:os')
const path = require('node:path')
const { execFile } = require('node:child_process')

const PROJECT_ROOT = path.resolve(__dirname, '..')
const TOKEN_FILE = path.join(os.homedir(), 'Library', 'Application Support', 'barong', 'google-calendar-token.json')
const STATE_FILE = path.join(os.homedir(), 'Library', 'Application Support', 'barong', 'google-calendar-state.json')
const SCOPES = ['https://www.googleapis.com/auth/calendar.events.readonly']

function loadEnv() {
  for (const filename of ['.env.local', '.env']) {
    const envPath = path.join(PROJECT_ROOT, filename)
    if (!fs.existsSync(envPath)) continue

    for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
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
  loadEnv()
  const clientId = process.env.GOOGLE_CLIENT_ID || ''
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET || ''

  if (!clientId || !clientSecret) {
    throw new Error('GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET are required in .env.local.')
  }

  return { clientId, clientSecret }
}

function ensureDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
}

function saveTokens(tokens) {
  ensureDir(TOKEN_FILE)
  fs.writeFileSync(TOKEN_FILE, JSON.stringify(tokens, null, 2))
}

function readTokens() {
  if (!fs.existsSync(TOKEN_FILE)) return null
  return JSON.parse(fs.readFileSync(TOKEN_FILE, 'utf8'))
}

function writeCalendarState(state) {
  ensureDir(STATE_FILE)
  fs.writeFileSync(
    STATE_FILE,
    JSON.stringify(
      {
        connected: false,
        events: [],
        updatedAt: new Date().toISOString(),
        ...state,
      },
      null,
      2,
    ),
  )
}

function createOAuthClient(redirectUri = 'http://127.0.0.1') {
  const { clientId, clientSecret } = getGoogleConfig()
  return new google.auth.OAuth2(clientId, clientSecret, redirectUri)
}

function createOAuthCallbackServer() {
  return new Promise((resolve, reject) => {
    const server = http.createServer()

    server.on('request', (request, response) => {
      const requestUrl = new URL(request.url || '/', `http://${request.headers.host}`)

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

function openExternal(targetUrl) {
  return new Promise((resolve, reject) => {
    execFile('open', [targetUrl], (error) => {
      if (error) reject(error)
      else resolve()
    })
  })
}

async function connect() {
  if (readTokens()) {
    await listEvents()
    return
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

  await openExternal(authUrl)
  try {
    const code = await codePromise
    const { tokens } = await oauth2Client.getToken(code)
    saveTokens(tokens)
    writeCalendarState({ connected: true, events: [] })
    await listEvents()
    console.log(JSON.stringify({ connected: true }))
  } finally {
    server.close()
  }
}

function getAuthedCalendarClient() {
  const tokens = readTokens()
  if (!tokens) return null

  const oauth2Client = createOAuthClient()
  oauth2Client.setCredentials(tokens)
  oauth2Client.on('tokens', (refreshedTokens) => {
    saveTokens({ ...tokens, ...refreshedTokens })
  })
  return google.calendar({ version: 'v3', auth: oauth2Client })
}

function getEventLocation(event) {
  if (event.location) return event.location

  const rooms = (event.attendees || [])
    .filter((attendee) => attendee.resource)
    .map((attendee) => attendee.displayName || attendee.email || '')
    .filter(Boolean)

  return rooms.join(', ')
}

async function listEvents() {
  const calendar = getAuthedCalendarClient()
  if (!calendar) {
    const result = { connected: false, events: [] }
    writeCalendarState(result)
    console.log(JSON.stringify(result))
    return
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
      location: getEventLocation(event),
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
  console.log(JSON.stringify(result))
}

async function main() {
  const command = process.argv[2]

  if (command === 'connect') {
    await connect()
    return
  }

  if (command === 'list') {
    await listEvents()
    return
  }

  if (command === 'status') {
    console.log(JSON.stringify({ connected: Boolean(readTokens()) }))
    return
  }

  throw new Error(`Unknown command: ${command || '(empty)'}`)
}

main().catch((error) => {
  writeCalendarState({
    connected: Boolean(readTokens()),
    events: [],
    error: error instanceof Error ? error.message : String(error),
  })
  console.error(error instanceof Error ? error.message : error)
  process.exit(1)
})
