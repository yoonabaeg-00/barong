export type CalendarStatus = {
  connected: boolean
  configured: boolean
}

export type CalendarEvent = {
  id: string
  title: string
  start: string
  end: string
  location: string
  htmlLink: string
  meetingLink: string
}

export type CalendarEventsResponse = {
  connected: boolean
  events: CalendarEvent[]
}

declare global {
  interface Window {
    barong?: {
      calendar: {
        getStatus: () => Promise<CalendarStatus>
        connect: () => Promise<{ connected: boolean }>
        disconnect: () => Promise<{ connected: boolean }>
        listEvents: () => Promise<CalendarEventsResponse>
      }
      openExternal: (url: string) => Promise<void>
      setExpanded: (expanded: boolean) => Promise<void>
    }
  }
}
