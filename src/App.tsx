import { useEffect, useMemo, useState } from 'react'
import barongSpritePreview from './assets/barong/barong-reference.png'
import './App.css'
import type { CalendarEvent, CalendarStatus } from './electron'

type PetMood = 'greet' | 'idle' | 'churu' | 'alert' | 'feed' | 'sleep'

const STORAGE_KEYS = {
  firstSeen: 'barong:first-seen-at',
  checkIn: 'barong:check-in-date',
  checkOut: 'barong:check-out-date',
}

function getTodayKey() {
  return new Date().toISOString().slice(0, 10)
}

function formatTime(value: string) {
  return new Intl.DateTimeFormat('ko-KR', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value))
}

function getDaysTogether(firstSeen: string | null) {
  if (!firstSeen) return 1
  const start = new Date(firstSeen)
  const now = new Date()
  const diff = now.getTime() - start.getTime()
  return Math.max(1, Math.floor(diff / 86400000) + 1)
}

function usePersistentBarongState() {
  const today = getTodayKey()
  const [firstSeen] = useState(() => {
    const stored = localStorage.getItem(STORAGE_KEYS.firstSeen)
    if (stored) return stored
    const created = new Date().toISOString()
    localStorage.setItem(STORAGE_KEYS.firstSeen, created)
    return created
  })
  const [checkedIn, setCheckedIn] = useState(
    () => localStorage.getItem(STORAGE_KEYS.checkIn) === today,
  )
  const [checkedOut, setCheckedOut] = useState(
    () => localStorage.getItem(STORAGE_KEYS.checkOut) === today,
  )

  return {
    daysTogether: getDaysTogether(firstSeen),
    checkedIn,
    checkedOut,
    checkIn: () => {
      localStorage.setItem(STORAGE_KEYS.checkIn, today)
      setCheckedIn(true)
    },
    checkOut: () => {
      localStorage.setItem(STORAGE_KEYS.checkOut, today)
      setCheckedOut(true)
    },
  }
}

function PlaceholderBarong({ mood }: { mood: PetMood }) {
  return (
    <div className={`barong-sprite ${mood}`} aria-label={`바롱이 ${mood}`}>
      <div className="ear left" />
      <div className="ear right" />
      <div className="head">
        <span className="eye left" />
        <span className="eye right" />
        <span className="nose" />
        <span className="mouth" />
      </div>
      <div className="paw left" />
      <div className="paw right" />
    </div>
  )
}

function AppMode() {
  const barong = usePersistentBarongState()
  const [expanded, setExpanded] = useState(false)
  const [mood, setMood] = useState<PetMood>('greet')
  const [message, setMessage] = useState('누나 왔어? 바롱이 기다렸어')
  const [calendarStatus, setCalendarStatus] = useState<CalendarStatus>({
    connected: false,
    configured: false,
  })
  const [events, setEvents] = useState<CalendarEvent[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const nextEvent = useMemo(() => {
    const now = Date.now()
    return events.find((event) => {
      const end = event.end ? new Date(event.end).getTime() : new Date(event.start).getTime()
      return end > now
    })
  }, [events])

  function toggleExpanded(next = !expanded) {
    setExpanded(next)
    window.barong?.setExpanded?.(next)
  }

  useEffect(() => {
    window.barong?.calendar.getStatus().then(setCalendarStatus).catch(() => {
      setCalendarStatus({ connected: false, configured: false })
    })
  }, [])

  useEffect(() => {
    if (!calendarStatus.connected) {
      setEvents([])
      return
    }

    const loadEvents = () => {
      window.barong?.calendar
        .listEvents()
        .then((response) => setEvents(response.events))
        .catch((eventError) => setError(eventError.message || '캘린더를 못 읽었어'))
    }

    loadEvents()
    const interval = window.setInterval(loadEvents, 60000)
    return () => window.clearInterval(interval)
  }, [calendarStatus.connected])

  useEffect(() => {
    if (!nextEvent) return

    const startsAt = new Date(nextEvent.start).getTime()
    const minutesLeft = Math.round((startsAt - Date.now()) / 60000)
    if (minutesLeft <= 10 && minutesLeft >= 0) {
      setMood('alert')
      setMessage(`누나 회의 ${minutesLeft || 1}분 남았어!`)
      toggleExpanded(true)
    }
  }, [nextEvent])

  async function connectCalendar() {
    setBusy(true)
    setError('')
    try {
      const result = await window.barong?.calendar.connect()
      if (result?.connected) {
        const status = await window.barong?.calendar.getStatus()
        if (status) setCalendarStatus(status)
        setMood('idle')
        setMessage('좋아! 이제 회의는 바롱이가 봐줄게')
        toggleExpanded(true)
      }
    } catch (connectError) {
      setError(
        connectError instanceof Error
          ? connectError.message
          : '캘린더 연결이 아직 안 됐어',
      )
    } finally {
      setBusy(false)
    }
  }

  function handleCheckIn() {
    barong.checkIn()
    setMood('churu')
    setMessage('츄르 냠! 출근 완료다 누나')
    window.setTimeout(() => {
      setMood('idle')
      setMessage('누나 열심히 해서 츄르 사줘~~')
    }, 1800)
  }

  function handleCheckOut() {
    barong.checkOut()
    setMood('feed')
    setMessage('밥 냠. 오늘도 같이 일했다!')
    window.setTimeout(() => {
      setMood('sleep')
      setMessage('내일도 바롱이 보러 와야 돼')
    }, 1800)
  }

  function openEvent(event: CalendarEvent) {
    if (event.meetingLink) {
      window.barong?.openExternal(event.meetingLink)
      return
    }
    if (event.htmlLink) window.barong?.openExternal(event.htmlLink)
  }

  return (
    <main className={`pet-shell ${expanded ? 'expanded' : 'collapsed'}`}>
      <button
        type="button"
        className="island-panel"
        aria-expanded={expanded}
        aria-label={expanded ? '바롱이 접기' : '바롱이 열기'}
        onClick={() => toggleExpanded()}
      >
        <div className="pet-stage">
          <PlaceholderBarong mood={mood} />
        </div>
        {expanded ? (
          <div className="pet-copy">
            <p className="eyebrow">Barong Island</p>
            <h1>{message}</h1>
            <p className="subcopy">바롱이랑 산 지 {barong.daysTogether}일째</p>
          </div>
        ) : null}
      </button>

      {expanded ? (
        <section className="island-body">
          <div className="expanded-summary">
            <p className="eyebrow">Barong Island</p>
            <h1>{message}</h1>
            <p className="subcopy">바롱이랑 산 지 {barong.daysTogether}일째</p>
          </div>

          {error ? <p className="error-note">{error}</p> : null}

          <section className="pet-actions" aria-label="바롱이 액션">
            {!calendarStatus.configured ? (
              <div className="setup-warning">
                <strong>Google OAuth 키가 필요해</strong>
                <span>.env.local에 GOOGLE_CLIENT_ID를 넣으면 연결 버튼이 열려.</span>
              </div>
            ) : (
              <button type="button" onClick={connectCalendar} disabled={busy}>
                {calendarStatus.connected ? '캘린더 연결됨' : '캘린더 연결하기'}
              </button>
            )}

            <button type="button" onClick={handleCheckIn} disabled={barong.checkedIn}>
              {barong.checkedIn ? '츄르 먹음' : '츄르주기'}
            </button>
            <button type="button" onClick={handleCheckOut} disabled={barong.checkedOut}>
              {barong.checkedOut ? '밥 먹음' : '밥주기'}
            </button>
          </section>

          {nextEvent ? (
            <section className="next-meeting">
              <p className="eyebrow">Next meeting</p>
              <button type="button" className="meeting-card" onClick={() => openEvent(nextEvent)}>
                <span>{formatTime(nextEvent.start)}</span>
                <strong>{nextEvent.title}</strong>
                <small>{nextEvent.location || nextEvent.meetingLink || '캘린더에서 보기'}</small>
              </button>
            </section>
          ) : null}
        </section>
      ) : null}
    </main>
  )
}

function LandingPage() {
  const downloadUrl = `${import.meta.env.BASE_URL}downloads/barong-notch-macos-poc.zip`

  return (
    <main className="landing-page">
      <section className="hero-section">
        <div className="hero-copy">
          <p className="eyebrow">macOS 업무 반려펫</p>
          <h1>바롱이 노치 앱</h1>
          <p>
            바롱이는 맥북 노치 우측에 사는 아비시니안 픽셀 고양이예요.
            Google Calendar를 연결하면 회의와 일정을 노치 아일랜드에 보여주고,
            츄르주기로 하루를 같이 시작해요.
          </p>
          <div className="hero-actions">
            <a href={downloadUrl} download>
              macOS 앱 다운로드
            </a>
            <a href="#privacy" className="secondary-link">
              캘린더 권한 보기
            </a>
          </div>
        </div>
        <div className="hero-visual" aria-label="바롱이 노치 이미지 모음">
          <img src={barongSpritePreview} alt="바롱이 노치 표정 모음" />
        </div>
      </section>

      <section className="feature-band">
        <article>
          <span>01</span>
          <h2>츄르주기</h2>
          <p>누나가 노트북을 켜면 바롱이가 나와요. 츄르를 주면 오늘 출근 완료.</p>
        </article>
        <article>
          <span>02</span>
          <h2>다음 일정</h2>
          <p>Google Calendar를 읽고 일정, 회의, 회의실, Meet 링크를 노치에 보여줘요.</p>
        </article>
        <article>
          <span>03</span>
          <h2>밥주기</h2>
          <p>퇴근할 때 밥을 주면 하루 마무리. 바롱이랑 산 날도 차곡차곡 쌓여요.</p>
        </article>
      </section>

      <section className="install-section">
        <div>
          <p className="eyebrow">Start</p>
          <h2>다운로드하고, 열고, 내 캘린더만 연결하면 끝.</h2>
        </div>
        <ol>
          <li>ZIP을 받아서 바롱이 앱을 실행해요.</li>
          <li>노치 아일랜드에서 Google Calendar를 연결해요.</li>
          <li>다음 일정이 있을 때만 바롱이가 카드로 보여줘요.</li>
        </ol>
      </section>

      <section className="calendar-demo">
        <div>
          <p className="eyebrow">Calendar alert</p>
          <h2>누나 다음 일정까지 10분 남았어!</h2>
          <p>AI 없이 규칙 기반으로 일정과 회의를 구분하고, 캘린더 데이터는 Mac 안에서만 처리해요.</p>
        </div>
        <div className="demo-island">
          <PlaceholderBarong mood="alert" />
          <div>
            <strong>14:00 주간 회의</strong>
            <span>현석타워-11-회의실1</span>
          </div>
        </div>
      </section>

      <section id="privacy" className="privacy-section">
        <h2>캘린더는 각자의 계정에서만</h2>
        <p>
          바롱이는 설치한 사람이 직접 연결한 Google Calendar만 읽어요. 일정 제목,
          시간, 장소, 회의 링크는 서버에 저장하지 않고 로컬 앱에서 아일랜드를 만들 때만 사용해요.
        </p>
      </section>
    </main>
  )
}

function App() {
  const params = new URLSearchParams(window.location.search)
  const mode = params.get('mode')
  return mode === 'app' ? <AppMode /> : <LandingPage />
}

export default App
