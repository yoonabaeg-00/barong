import AppKit
import CoreGraphics
import CoreText
import Foundation
import Network

private enum BarongResources {
    static func url(forResource resource: String, withExtension fileExtension: String) -> URL? {
        let fileName = "\(resource).\(fileExtension)"
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(fileName))
            candidates.append(
                resourceURL
                    .appendingPathComponent("BarongNotch_BarongNotch.bundle")
                    .appendingPathComponent(fileName)
            )
        }

        candidates.append(
            Bundle.main.bundleURL
                .appendingPathComponent("BarongNotch_BarongNotch.bundle")
                .appendingPathComponent(fileName)
        )

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            return url
        }

        return Bundle.module.url(forResource: resource, withExtension: fileExtension)
    }
}

@MainActor
private enum BarongFonts {
    private static var registeredNames: [String: String] = [:]

    static func talk(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        font(resource: "BarongTalk", extension: "ttf", size: size, fallbackWeight: weight)
    }

    static func ui(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let resource: String
        switch weight {
        case .heavy, .black:
            resource = "Pretendard-ExtraBold"
        case .bold:
            resource = "Pretendard-Bold"
        case .semibold, .medium:
            resource = "Pretendard-SemiBold"
        default:
            resource = "Pretendard-Regular"
        }

        return font(resource: resource, extension: "otf", size: size, fallbackWeight: weight)
    }

    private static func font(
        resource: String,
        extension fileExtension: String,
        size: CGFloat,
        fallbackWeight: NSFont.Weight
    ) -> NSFont {
        if let name = registeredNames[resource] ?? registerFont(resource: resource, extension: fileExtension),
           let customFont = NSFont(name: name, size: size) {
            return customFont
        }

        return .systemFont(ofSize: size, weight: fallbackWeight)
    }

    private static func registerFont(resource: String, extension fileExtension: String) -> String? {
        guard let url = BarongResources.url(forResource: resource, withExtension: fileExtension),
              let dataProvider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(dataProvider) else {
            return nil
        }

        var error: Unmanaged<CFError>?
        CTFontManagerRegisterGraphicsFont(cgFont, &error)

        let name = cgFont.postScriptName as String?
        registeredNames[resource] = name
        return name
    }
}

private enum BarongIslandState {
    case collapsed
    case expanded
}

private enum BarongIslandLayout {
    static let minimumExpandedHeight: CGFloat = 292
    static let minimumSingleMeetingExpandedHeight: CGFloat = 258
    static let minimumCompactExpandedHeight: CGFloat = 174
    static let contentLift: CGFloat = 18
    static let horizontalPadding: CGFloat = 36
    static let topPadding: CGFloat = 38
    static let heroHeight: CGFloat = 46
    static let heroSubtitleGap: CGFloat = -4
    static let subtitleHeight: CGFloat = 20
    static let subtitleButtonGap: CGFloat = 14
    static let buttonGap: CGFloat = 16
    static let buttonHeight: CGFloat = 44
    static let buttonMeetingGap: CGFloat = 18
    static let meetingPadding: CGFloat = 22
    static let meetingTopPadding: CGFloat = 16
    static let meetingBottomPadding: CGFloat = 16
    static let singleMeetingHeight: CGFloat = 92
    static let doubleMeetingHeight: CGFloat = 124
    static let bottomPadding: CGFloat = 28
    static let compactBottomPadding: CGFloat = 22
    static let compactExpandedWidth: CGFloat = 440
    static let doubleMeetingExpandedWidth: CGFloat = 520

    static var expandedHeight: CGFloat {
        expandedHeight(meetingCount: 1)
    }

    static func expandedHeight(hasMeeting: Bool) -> CGFloat {
        expandedHeight(meetingCount: hasMeeting ? 1 : 0)
    }

    static func meetingHeight(count: Int) -> CGFloat {
        if count <= 0 { return 0 }
        return count > 1 ? doubleMeetingHeight : singleMeetingHeight
    }

    static func expandedWidth(meetingCount: Int) -> CGFloat {
        meetingCount > 1 ? doubleMeetingExpandedWidth : compactExpandedWidth
    }

    static func expandedHeight(meetingCount: Int) -> CGFloat {
        let visibleMeetingCount = min(2, max(0, meetingCount))
        let hasMeeting = visibleMeetingCount > 0
        let contentHeight = topPadding
            + heroHeight
            + heroSubtitleGap
            + subtitleHeight
            + subtitleButtonGap
            + buttonHeight
            + (hasMeeting ? bottomPadding : compactBottomPadding)
            - contentLift

        if !hasMeeting {
            return max(minimumCompactExpandedHeight, contentHeight)
        }

        let minimumHeight = visibleMeetingCount > 1
            ? minimumExpandedHeight
            : minimumSingleMeetingExpandedHeight

        return max(
            minimumHeight,
            contentHeight
                + buttonMeetingGap
                + meetingHeight(count: visibleMeetingCount)
        )
    }
}

private struct BarongNotchMetrics {
    let screen: NSScreen
    let notchSize: CGSize
    let windowHeight: CGFloat = 520

    var windowFrame: NSRect {
        let frame = screen.frame
        return NSRect(
            x: frame.minX,
            y: frame.maxY - windowHeight,
            width: frame.width,
            height: windowHeight
        )
    }

    func collapsedRect(in bounds: NSRect) -> NSRect {
        let rightTail: CGFloat = max(72, notchSize.height * 1.8)
        let leftTail: CGFloat = 10
        let width = notchSize.width + leftTail + rightTail
        let height = max(34, notchSize.height + 2)
        let notchLeft = bounds.midX - notchSize.width / 2

        return NSRect(
            x: notchLeft - leftTail,
            y: bounds.maxY - height,
            width: width,
            height: height
        )
    }

    func expandedRect(in bounds: NSRect, meetingCount: Int) -> NSRect {
        let horizontalScreenPadding: CGFloat = 20
        let availableWidth = bounds.width - (horizontalScreenPadding * 2)
        let width = min(BarongIslandLayout.expandedWidth(meetingCount: meetingCount), availableWidth)
        let height = BarongIslandLayout.expandedHeight(meetingCount: meetingCount)

        return NSRect(
            x: bounds.midX - width / 2,
            y: bounds.maxY - height,
            width: width,
            height: height
        )
    }
}

private extension NSScreen {
    static var barongBuiltInOrMain: NSScreen {
        screens.first { $0.barongIsBuiltIn } ?? main ?? screens[0]
    }

    var barongIsBuiltIn: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }

        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    var barongNotchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(width: 224, height: 38)
        }

        let leftWidth = auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = auxiliaryTopRightArea?.width ?? 0
        let measuredWidth = frame.width - leftWidth - rightWidth
        let menuBarHeight = frame.maxY - visibleFrame.maxY

        return CGSize(
            width: min(260, max(180, measuredWidth + 4)),
            height: max(32, max(safeAreaInsets.top, menuBarHeight))
        )
    }
}

@MainActor
final class BarongApp: NSObject, NSApplicationDelegate {
    private var controller: BarongNotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = BarongNotchController()
        controller?.show()
    }
}

let app = NSApplication.shared
let delegate = BarongApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

@MainActor
private final class BarongNotchController {
    private let panel: BarongNotchPanel
    private let contentView: BarongNotchView
    private var outsideClickMonitor: Any?

    init() {
        let screen = NSScreen.barongBuiltInOrMain
        let metrics = BarongNotchMetrics(screen: screen, notchSize: screen.barongNotchSize)

        panel = BarongNotchPanel(frame: metrics.windowFrame)
        contentView = BarongNotchView(frame: NSRect(origin: .zero, size: metrics.windowFrame.size), metrics: metrics)
        panel.contentView = contentView

        contentView.onToggle = { [weak self] in
            self?.contentView.toggle()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.contentView.collapseIfExpandedByOutsideClick(at: event.locationInWindow)
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let outsideClickMonitor {
                NSEvent.removeMonitor(outsideClickMonitor)
            }
        }
    }

    func show() {
        panel.orderFrontRegardless()
    }

    @objc private func handleScreenChange() {
        let screen = NSScreen.barongBuiltInOrMain
        let metrics = BarongNotchMetrics(screen: screen, notchSize: screen.barongNotchSize)
        panel.setFrame(metrics.windowFrame, display: true)
        contentView.frame = NSRect(origin: .zero, size: metrics.windowFrame.size)
        contentView.update(metrics: metrics)
    }
}

private final class BarongNotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct BarongCalendarState: Codable {
    let connected: Bool
    let events: [BarongCalendarEvent]
    let updatedAt: String?
    let error: String?

    init(
        connected: Bool,
        events: [BarongCalendarEvent],
        updatedAt: String? = ISO8601DateFormatter().string(from: Date()),
        error: String? = nil
    ) {
        self.connected = connected
        self.events = events
        self.updatedAt = updatedAt
        self.error = error
    }
}

private struct BarongCalendarEvent: Codable {
    let id: String
    let title: String
    let start: String
    let end: String?
    let location: String?
    let htmlLink: String?
    let meetingLink: String?
    let kind: String?

    var startDate: Date? {
        Self.parseDate(start)
    }

    var endDate: Date? {
        guard let end else { return nil }
        return Self.parseDate(end)
    }

    var bestURL: URL? {
        let rawURL = [meetingLink, htmlLink]
            .compactMap { $0 }
            .first { !$0.isEmpty }

        guard let rawURL else { return nil }
        return URL(string: rawURL)
    }

    var formattedStartTime: String {
        guard let startDate else { return "--:--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: startDate)
    }

    var isMeeting: Bool {
        if kind == "meeting" { return true }
        if meetingLink?.isEmpty == false { return true }
        if location?.isEmpty == false { return true }

        let keywords = ["회의", "미팅", "1:1", "sync", "standup", "review", "meeting"]
        let lowercasedTitle = title.lowercased()
        return keywords.contains { lowercasedTitle.contains($0) }
    }

    private static func parseDate(_ rawValue: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: rawValue) {
            return date
        }

        let fractionalIsoFormatter = ISO8601DateFormatter()
        fractionalIsoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalIsoFormatter.date(from: rawValue)
    }
}

private struct BarongOAuthCredentials: Decodable {
    let clientId: String
    let clientSecret: String
}

private struct BarongOAuthToken: Codable {
    let accessToken: String?
    let refreshToken: String?
    let expiryDate: Date?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiryDate = "expiry_date"
    }

    init(accessToken: String?, refreshToken: String?, expiryDate: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiryDate = expiryDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)

        if let date = try? container.decodeIfPresent(Date.self, forKey: .expiryDate) {
            expiryDate = date
        } else if let timestamp = try? container.decodeIfPresent(Double.self, forKey: .expiryDate) {
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
            expiryDate = Date(timeIntervalSince1970: seconds)
        } else if let value = try? container.decodeIfPresent(String.self, forKey: .expiryDate) {
            expiryDate = ISO8601DateFormatter().date(from: value)
        } else {
            expiryDate = nil
        }
    }
}

private actor BarongCalendarClient {
    static let shared = BarongCalendarClient()

    private let scopes = ["https://www.googleapis.com/auth/calendar.events.readonly"]
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var appSupportURL: URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent("barong", isDirectory: true)
    }

    private var tokenURL: URL {
        appSupportURL.appendingPathComponent("google-calendar-token.json")
    }

    private var stateURL: URL {
        appSupportURL.appendingPathComponent("google-calendar-state.json")
    }

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func status() -> Bool {
        readToken()?.refreshToken?.isEmpty == false
    }

    func writeErrorState(_ error: Error) {
        let state = BarongCalendarState(
            connected: status(),
            events: [],
            error: String(describing: error)
        )
        try? saveState(state)
    }

    func connect() async throws -> BarongCalendarState {
        if status() {
            return try await listEvents()
        }

        let credentials = try readCredentials()
        let callback = try await OAuthCallback.start()
        let redirectURI = "http://127.0.0.1:\(callback.port)/oauth2callback"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authURL = components.url else {
            throw CalendarError.invalidAuthURL
        }

        await MainActor.run {
            _ = NSWorkspace.shared.open(authURL)
        }

        let code = try await callback.waitForCode()
        let token = try await exchangeCode(code, redirectURI: redirectURI, credentials: credentials)
        try saveToken(token)
        return try await listEvents()
    }

    func listEvents() async throws -> BarongCalendarState {
        guard let accessToken = try await validAccessToken() else {
            let state = BarongCalendarState(connected: false, events: [])
            try saveState(state)
            return state
        }

        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
        let isoFormatter = ISO8601DateFormatter()

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: isoFormatter.string(from: now)),
            URLQueryItem(name: "timeMax", value: isoFormatter.string(from: tomorrow)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "10"),
            URLQueryItem(name: "showDeleted", value: "false")
        ]

        guard let url = components.url else {
            throw CalendarError.invalidCalendarURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data = try await send(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = json?["items"] as? [[String: Any]] ?? []
        let events = items.compactMap(parseEvent)
        let state = BarongCalendarState(connected: true, events: events)
        try saveState(state)
        return state
    }

    private func parseEvent(_ event: [String: Any]) -> BarongCalendarEvent? {
        guard
            let start = event["start"] as? [String: Any],
            let startDateTime = start["dateTime"] as? String
        else {
            return nil
        }

        if event["status"] as? String == "cancelled" { return nil }
        if event["transparency"] as? String == "transparent" { return nil }

        let attendees = event["attendees"] as? [[String: Any]] ?? []
        let declinedBySelf = attendees.contains { attendee in
            (attendee["self"] as? Bool == true) && (attendee["responseStatus"] as? String == "declined")
        }
        if declinedBySelf { return nil }

        let conferenceData = event["conferenceData"] as? [String: Any]
        let entryPoints = conferenceData?["entryPoints"] as? [[String: Any]] ?? []
        let meetingLink = event["hangoutLink"] as? String
            ?? entryPoints.first {
                let type = $0["entryPointType"] as? String
                return type == "video" || type == "more"
            }?["uri"] as? String

        let resourceRooms = attendees
            .filter { $0["resource"] as? Bool == true }
            .compactMap { ($0["displayName"] as? String) ?? ($0["email"] as? String) }
            .filter { !$0.isEmpty }
        let location = (event["location"] as? String)?.isEmpty == false
            ? event["location"] as? String
            : resourceRooms.joined(separator: ", ")
        let guestCount = attendees.filter { $0["resource"] as? Bool != true }.count
        let title = event["summary"] as? String ?? "제목 없는 일정"
        let kind = inferEventKind(title: title, location: location ?? "", meetingLink: meetingLink ?? "", guestCount: guestCount)
        let end = event["end"] as? [String: Any]

        return BarongCalendarEvent(
            id: event["id"] as? String ?? UUID().uuidString,
            title: title,
            start: startDateTime,
            end: end?["dateTime"] as? String,
            location: location ?? "",
            htmlLink: event["htmlLink"] as? String ?? "",
            meetingLink: meetingLink ?? "",
            kind: kind
        )
    }

    private func inferEventKind(title: String, location: String, meetingLink: String, guestCount: Int) -> String {
        if !meetingLink.isEmpty || !location.isEmpty || guestCount >= 2 {
            return "meeting"
        }

        let lowercasedTitle = title.lowercased()
        let keywords = ["회의", "미팅", "1:1", "sync", "standup", "review", "meeting"]
        if keywords.contains(where: { lowercasedTitle.contains($0) }) {
            return "meeting"
        }

        return "schedule"
    }

    private func validAccessToken() async throws -> String? {
        guard let token = readToken() else { return nil }

        if let accessToken = token.accessToken,
           let expiryDate = token.expiryDate,
           expiryDate.timeIntervalSinceNow > 60 {
            return accessToken
        }

        guard let refreshToken = token.refreshToken, !refreshToken.isEmpty else {
            return token.accessToken
        }

        let refreshedToken = try await refreshAccessToken(refreshToken)
        try saveToken(refreshedToken)
        return refreshedToken.accessToken
    }

    private func exchangeCode(
        _ code: String,
        redirectURI: String,
        credentials: BarongOAuthCredentials
    ) async throws -> BarongOAuthToken {
        let body = [
            "code": code,
            "client_id": credentials.clientId,
            "client_secret": credentials.clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]

        return try await tokenRequest(body)
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> BarongOAuthToken {
        let credentials = try readCredentials()
        let body = [
            "refresh_token": refreshToken,
            "client_id": credentials.clientId,
            "client_secret": credentials.clientSecret,
            "grant_type": "refresh_token"
        ]
        let token = try await tokenRequest(body)
        return BarongOAuthToken(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken ?? refreshToken,
            expiryDate: token.expiryDate
        )
    }

    private func tokenRequest(_ body: [String: String]) async throws -> BarongOAuthToken {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key.urlEncoded)=\($0.value.urlEncoded)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let data = try await send(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let expiresIn = json?["expires_in"] as? TimeInterval ?? 3600

        return BarongOAuthToken(
            accessToken: json?["access_token"] as? String,
            refreshToken: json?["refresh_token"] as? String,
            expiryDate: Date().addingTimeInterval(expiresIn)
        )
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CalendarError.requestFailed(body)
        }
        return data
    }

    private func readToken() -> BarongOAuthToken? {
        guard let data = try? Data(contentsOf: tokenURL) else { return nil }
        return try? decoder.decode(BarongOAuthToken.self, from: data)
    }

    private func saveToken(_ token: BarongOAuthToken) throws {
        try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        let data = try encoder.encode(token)
        try data.write(to: tokenURL, options: .atomic)
    }

    private func saveState(_ state: BarongCalendarState) throws {
        try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    private func readCredentials() throws -> BarongOAuthCredentials {
        let urls = credentialURLs()

        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let credentials = try? decoder.decode(BarongOAuthCredentials.self, from: data) {
                return credentials
            }

            if let envCredentials = parseEnvCredentials(data) {
                return envCredentials
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let installed = (json["installed"] as? [String: Any]) ?? (json["web"] as? [String: Any]),
               let clientId = installed["client_id"] as? String,
               let clientSecret = installed["client_secret"] as? String {
                return BarongOAuthCredentials(clientId: clientId, clientSecret: clientSecret)
            }
        }

        throw CalendarError.missingCredentials
    }

    private func parseEnvCredentials(_ data: Data) -> BarongOAuthCredentials? {
        guard let content = String(data: data, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]

        for rawLine in content.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || !line.contains("=") { continue }
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            values[key] = value
        }

        guard let clientId = values["GOOGLE_CLIENT_ID"],
              let clientSecret = values["GOOGLE_CLIENT_SECRET"],
              !clientId.isEmpty,
              !clientSecret.isEmpty else {
            return nil
        }

        return BarongOAuthCredentials(clientId: clientId, clientSecret: clientSecret)
    }

    private func credentialURLs() -> [URL] {
        var urls: [URL] = []
        if let moduleURL = BarongResources.url(forResource: "GoogleOAuth", withExtension: "json") {
            urls.append(moduleURL)
        }
        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("GoogleOAuth.json"))
            urls.append(resourceURL.appendingPathComponent("BarongNotch_BarongNotch.bundle/GoogleOAuth.json"))
        }
        urls.append(Bundle.main.bundleURL.appendingPathComponent("BarongNotch_BarongNotch.bundle/GoogleOAuth.json"))
        urls.append(URL(fileURLWithPath: "/Users/baegyoona/Desktop/해커톤/native/BarongNotch/Sources/Resources/GoogleOAuth.json"))
        urls.append(URL(fileURLWithPath: "/Users/baegyoona/Desktop/해커톤/.env.local"))
        return urls
    }

    private enum CalendarError: Error {
        case missingCredentials
        case invalidAuthURL
        case invalidCalendarURL
        case requestFailed(String)
    }
}

private final class OAuthCallback: @unchecked Sendable {
    let port: UInt16
    private let listener: NWListener
    private var continuation: CheckedContinuation<String, Error>?

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    static func start() async throws -> OAuthCallback {
        let parameters = NWParameters.tcp
        let listener = try NWListener(using: parameters, on: .any)

        guard let port = listener.port else {
            throw CallbackError.noPort
        }

        let callback = OAuthCallback(listener: listener, port: port.rawValue)
        listener.newConnectionHandler = { connection in
            callback.handle(connection)
        }
        listener.start(queue: .main)
        return callback
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
            if let error {
                self.continuation?.resume(throwing: error)
                self.listener.cancel()
                return
            }

            guard
                let data,
                let request = String(data: data, encoding: .utf8),
                let firstLine = request.split(separator: "\r\n").first
            else {
                self.respond(connection, success: false)
                self.continuation?.resume(throwing: CallbackError.invalidRequest)
                self.listener.cancel()
                return
            }

            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else {
                self.respond(connection, success: false)
                self.continuation?.resume(throwing: CallbackError.invalidRequest)
                self.listener.cancel()
                return
            }

            let path = String(parts[1])
            let url = URL(string: "http://127.0.0.1\(path)")
            let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }

            if let errorValue = components?.queryItems?.first(where: { $0.name == "error" })?.value {
                self.respond(connection, success: false)
                self.continuation?.resume(throwing: CallbackError.oauth(errorValue))
                self.listener.cancel()
                return
            }

            guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value else {
                self.respond(connection, success: false)
                self.continuation?.resume(throwing: CallbackError.missingCode)
                self.listener.cancel()
                return
            }

            self.respond(connection, success: true)
            self.continuation?.resume(returning: code)
            self.listener.cancel()
        }
    }

    private func respond(_ connection: NWConnection, success: Bool) {
        let message = success ? "연결됐어요. 이 창은 닫아도 돼요." : "연결이 완료되지 않았어요."
        let body = """
        <html><body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px"><h2>바롱이 캘린더 연결</h2><p>\(message)</p></body></html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private enum CallbackError: Error {
        case noPort
        case invalidRequest
        case missingCode
        case oauth(String)
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

@MainActor
private final class BarongNotchView: NSView {
    var onToggle: (() -> Void)?

    private enum ActionTarget: Equatable {
        case churu
        case greeting
        case meeting
    }

    private struct ExpandedHitZones {
        let churu: NSRect
        let greeting: NSRect
        let meeting: NSRect
    }

    private enum NotchMood {
        case idle
        case laugh
        case smile
        case churu
        case cheer
        case sleepy

        var resourcePrefix: String {
            switch self {
            case .idle: "NotchIdle"
            case .laugh: "NotchLaugh"
            case .smile: "NotchSmile"
            case .churu: "NotchChuru"
            case .cheer: "NotchCheer"
            case .sleepy: "NotchSleepy"
            }
        }
    }

    private struct HeartParticle {
        let startedAt: TimeInterval
        let duration: TimeInterval
        let start: NSPoint
        let rise: CGFloat
        let drift: CGFloat
        let size: CGFloat
        let opacity: CGFloat
    }

    private var metrics: BarongNotchMetrics
    private var state: BarongIslandState = .collapsed
    private var expansion: CGFloat = 0
    private var animationTimer: Timer?
    private var spriteTimer: Timer?
    private var heartTimer: Timer?
    private var calendarTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private var hoveredTarget: ActionTarget?
    private var notchMood: NotchMood = .idle
    private var notchImageCache: [String: [NSImage]] = [:]
    private var heartImageCache: NSImage?
    private var heartParticles: [HeartParticle] = []
    private var calendarConnected = false
    private var calendarBusy = false
    private var calendarRefreshInFlight = false
    private var nextMeetings: [BarongCalendarEvent] = []
    private var nextMeeting: BarongCalendarEvent? {
        nextMeetings.first
    }
    private var alertedMeetingID: String?
    private let joinedDays = 1
    private var heroMessage = "바롱이 츄르 먹고싶어"

    init(frame frameRect: NSRect, metrics: BarongNotchMetrics) {
        self.metrics = metrics
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        startSpriteAnimation()
        startCalendarSync()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        MainActor.assumeIsolated {
            spriteTimer?.invalidate()
            heartTimer?.invalidate()
            calendarTimer?.invalidate()
        }
    }

    func update(metrics: BarongNotchMetrics) {
        self.metrics = metrics
        needsDisplay = true
    }

    func toggle() {
        state = state == .collapsed ? .expanded : .collapsed
        animateExpansion(to: state == .expanded ? 1 : 0)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        interactionRect.insetBy(dx: -8, dy: -8).contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let nextTarget = state == .expanded ? actionTarget(at: point, in: expandedRect) : nil

        if state == .collapsed, collapsedRect.contains(point), notchMood == .idle {
            notchMood = .smile
            needsDisplay = true
        }

        if nextTarget != hoveredTarget {
            hoveredTarget = nextTarget
            needsDisplay = true
        }

        if nextTarget == nil {
            NSCursor.arrow.set()
        } else {
            NSCursor.pointingHand.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredTarget = nil
        if state == .collapsed {
            notchMood = .idle
        }
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch state {
        case .collapsed:
            expand()
        case .expanded:
            if let target = actionTarget(at: point, in: expandedRect) {
                handleAction(target)
                return
            }

            collapse()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()

        let islandRect = currentIslandRect
        drawIslandShell(in: islandRect)

        if expansion < 0.16 {
            drawCollapsedBarong(in: islandRect, opacity: Double(1 - (expansion / 0.16)))
        }

        if expansion > 0.58 {
            drawExpandedContent(in: islandRect, opacity: Double((expansion - 0.58) / 0.42))
        }
    }

    private var collapsedRect: NSRect {
        metrics.collapsedRect(in: bounds)
    }

    private var expandedRect: NSRect {
        let baseRect = metrics.expandedRect(in: bounds, meetingCount: nextMeetings.count)

        return NSRect(
            x: baseRect.minX,
            y: bounds.maxY - baseRect.height,
            width: baseRect.width,
            height: baseRect.height
        )
    }

    private var currentIslandRect: NSRect {
        let from = collapsedRect
        let to = expandedRect

        return NSRect(
            x: interpolate(from.minX, to.minX),
            y: interpolate(from.minY, to.minY),
            width: interpolate(from.width, to.width),
            height: interpolate(from.height, to.height)
        )
    }

    private var interactionRect: NSRect {
        state == .expanded ? expandedRect : collapsedRect
    }

    private func expand() {
        state = .expanded
        notchMood = .laugh
        refreshCalendarState()
        refreshCalendarFromGoogle()
        showHeroMessage(from: [
            "누나 뭐해",
            "바롱이 츄르 먹고싶어",
            "누나 집중안하지!!",
            "바롱이 왔다~~",
            "누나 오늘도 츄르 벌자",
            "바롱이는 지켜보고 있다",
            "누나 일하는 척 하는 거 아니지?",
            "누나 커피 마셨어?",
            "오늘도 바롱이가 같이 있어줄게",
            "누나 바쁘면 바롱이는 혼자 놀게~",
            "누나 손 느려졌다!",
            "바롱이 심심해",
            "누나 집중하면 츄르 하나 추가!"
        ])
        animateExpansion(to: 1)
    }

    private func collapse() {
        state = .collapsed
        hoveredTarget = nil
        heartParticles.removeAll()
        heartTimer?.invalidate()
        heartTimer = nil
        NSCursor.arrow.set()
        animateExpansion(to: 0)
    }

    func collapseIfExpandedByOutsideClick(at screenPoint: NSPoint) {
        guard state == .expanded else { return }
        collapse()
    }

    private func expandedHitZones(in rect: NSRect) -> ExpandedHitZones {
        let horizontalPadding = BarongIslandLayout.horizontalPadding
        let meetingY = rect.minY + BarongIslandLayout.bottomPadding
        let buttonY = if nextMeeting == nil {
            rect.minY + BarongIslandLayout.compactBottomPadding
        } else {
            meetingY + BarongIslandLayout.meetingHeight(count: nextMeetings.count) + BarongIslandLayout.buttonMeetingGap
        }
        let buttonWidth = (rect.width - (horizontalPadding * 2) - BarongIslandLayout.buttonGap) / 2

        return ExpandedHitZones(
            churu: NSRect(
                x: rect.minX + horizontalPadding + buttonWidth + BarongIslandLayout.buttonGap,
                y: buttonY,
                width: buttonWidth,
                height: BarongIslandLayout.buttonHeight
            ),
            greeting: NSRect(x: rect.minX + horizontalPadding, y: buttonY, width: buttonWidth, height: BarongIslandLayout.buttonHeight),
            meeting: NSRect(
                x: rect.minX + horizontalPadding,
                y: meetingY,
                width: rect.width - (horizontalPadding * 2),
                height: BarongIslandLayout.meetingHeight(count: nextMeetings.count)
            )
        )
    }

    private func actionTarget(at point: NSPoint, in rect: NSRect) -> ActionTarget? {
        let zones = expandedHitZones(in: rect)

        if zones.churu.contains(point) { return .churu }
        if zones.greeting.contains(point) { return .greeting }
        if nextMeeting != nil, zones.meeting.contains(point) { return .meeting }

        return nil
    }

    private func handleAction(_ target: ActionTarget) {
        switch target {
        case .churu:
            notchMood = .churu
            emitChuruHearts()
            showHeroMessage(from: [
                "출석체크 완료!",
                "누나 오늘도 츄르 벌자~~",
                "바롱이가 출근 도장 찍어줬어",
                "누나 열심히해서 츄르사줘~~",
                "오늘 하루 시작이다 누나!",
                "바롱이도 같이 출근했어",
                "누나 오늘은 일찍 끝내자",
                "츄르 받을 준비 완료!",
                "출근했으니까 바롱이 쓰담!",
                "누나 오늘도 할 수 있다",
                "바롱이가 응원할게~~",
                "누나 일하면 바롱이는 옆에서 잘게"
            ])
        case .greeting:
            if !calendarConnected {
                connectCalendar()
                return
            }

            notchMood = .laugh
            showHeroMessage(from: [
                "누나 안녕~~",
                "바롱이 왔다!",
                "누나 커피 마셨어?",
                "누나 손 흔들어줘~~",
                "바롱이는 놀러갈거야~",
                "누나 집중안하지!!",
                "바롱이랑 인사했으니까 일하자"
            ])
        case .meeting:
            notchMood = .cheer
            if let meetingURL = nextMeeting?.bestURL {
                NSWorkspace.shared.open(meetingURL)
            }
            showHeroMessage(from: [
                "누나 회의 늦으면 안돼!",
                meetingLocationMessage,
                "바롱이가 10분 전에 알려줬어",
                "누나 발표 준비했지?",
                "회의 전에 물 한 모금!",
                "누나 카메라 켤 준비했어?",
                "자료 열어놔 누나!",
                "바롱이는 회의 안 갈래~",
                "누나 말할 차례 오면 당황하지마",
                "회의 끝나면 츄르 줘",
                "중요한 회의면 바롱이도 얌전히 있을게"
            ])
        }

        needsDisplay = true
    }

    private func showHeroMessage(from messages: [String]) {
        guard !messages.isEmpty else { return }
        guard messages.count > 1 else {
            heroMessage = messages[0]
            return
        }

        var nextMessage = messages.randomElement() ?? messages[0]
        while nextMessage == heroMessage {
            nextMessage = messages.randomElement() ?? messages[0]
        }
        heroMessage = nextMessage
    }

    private func animateExpansion(to target: CGFloat) {
        animationTimer?.invalidate()

        let start = expansion
        let startedAt = CACurrentMediaTime()
        let duration = 0.24

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self else {
                    return
                }

                let elapsed = CACurrentMediaTime() - startedAt
                let rawProgress = min(1, elapsed / duration)
                let eased = 1 - pow(1 - rawProgress, 3)
                self.expansion = start + ((target - start) * eased)
                self.needsDisplay = true

                if rawProgress >= 1 {
                    self.expansion = target
                    self.needsDisplay = true
                    self.animationTimer?.invalidate()
                    self.animationTimer = nil
                }
            }
        }

        RunLoop.main.add(animationTimer!, forMode: .common)
    }

    private func startSpriteAnimation() {
        spriteTimer?.invalidate()
        spriteTimer = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                self?.needsDisplay = true
            }
        }
        RunLoop.main.add(spriteTimer!, forMode: .common)
    }

    private func startCalendarSync() {
        refreshCalendarState()
        refreshCalendarFromGoogle()
        calendarTimer?.invalidate()
        calendarTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                self?.refreshCalendarFromGoogle()
            }
        }
        RunLoop.main.add(calendarTimer!, forMode: .common)
    }

    private func refreshCalendarFromGoogle() {
        guard calendarConnected, !calendarRefreshInFlight else { return }

        calendarRefreshInFlight = true
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await BarongCalendarClient.shared.listEvents()
            } catch {
                await BarongCalendarClient.shared.writeErrorState(error)
            }

            await MainActor.run {
                self.refreshCalendarState()
                self.calendarRefreshInFlight = false
                self.needsDisplay = true
            }
        }
    }

    private func refreshCalendarState() {
        let previousID = nextMeeting?.id
        let snapshot = loadCalendarSnapshot()
        calendarConnected = snapshot.connected
        nextMeetings = snapshot.meetings

        if previousID != nextMeeting?.id {
            hoveredTarget = hoveredTarget == .meeting && nextMeeting == nil ? nil : hoveredTarget
            needsDisplay = true
        }

        guard let nextMeeting,
              nextMeeting.id != alertedMeetingID,
              let startDate = nextMeeting.startDate else {
            return
        }

        let secondsUntilStart = startDate.timeIntervalSinceNow
        guard secondsUntilStart >= 0, secondsUntilStart <= 600 else { return }

        alertedMeetingID = nextMeeting.id
        let minutesLeft = max(1, Int(ceil(secondsUntilStart / 60)))
        heroMessage = "누나 회의 \(minutesLeft)분 남았어!"
        notchMood = .cheer
        state = .expanded
        animateExpansion(to: 1)
    }

    private func loadCalendarSnapshot() -> (connected: Bool, meetings: [BarongCalendarEvent]) {
        let decoder = JSONDecoder()
        let now = Date()
        let hasToken = hasStoredCalendarToken()

        for url in calendarStateURLs {
            guard let data = try? Data(contentsOf: url),
                  let state = try? decoder.decode(BarongCalendarState.self, from: data) else {
                continue
            }

            let meetings = state.events
                .filter { event in
                    guard let start = event.startDate else { return false }
                    let end = event.endDate ?? start
                    return end > now
                }
                .sorted { lhs, rhs in
                    guard let lhsDate = lhs.startDate, let rhsDate = rhs.startDate else { return false }
                    return lhsDate < rhsDate
                }

            return (state.connected || hasToken, Array(meetings.prefix(2)))
        }

        return (hasToken, [])
    }

    private var calendarStateURLs: [URL] {
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return []
        }

        return ["barong", "바롱이"].map {
            appSupportURL
                .appendingPathComponent($0, isDirectory: true)
                .appendingPathComponent("google-calendar-state.json")
        }
    }

    private func hasStoredCalendarToken() -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for url in calendarTokenURLs {
            guard let data = try? Data(contentsOf: url),
                  let token = try? decoder.decode(BarongOAuthToken.self, from: data),
                  token.refreshToken?.isEmpty == false else {
                continue
            }

            return true
        }

        return false
    }

    private var calendarTokenURLs: [URL] {
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return []
        }

        return ["barong", "바롱이"].map {
            appSupportURL
                .appendingPathComponent($0, isDirectory: true)
                .appendingPathComponent("google-calendar-token.json")
        }
    }

    private var meetingLocationMessage: String {
        guard let location = nextMeeting?.location, !location.isEmpty else {
            return "링크도 찾았어. 바롱이 똑똑하지?"
        }
        return "\(location)로 가면 돼"
    }

    private var calendarButtonTitle: String {
        if calendarBusy {
            return "연결 중"
        }
        return calendarConnected ? "인사하기" : "캘린더 연결"
    }

    private func connectCalendar() {
        guard !calendarBusy else { return }

        calendarBusy = true
        notchMood = .cheer
        heroMessage = "브라우저에서 구글 허용해줘"
        needsDisplay = true

        Task { [weak self] in
            guard let self else { return }
            let success: Bool

            do {
                _ = try await BarongCalendarClient.shared.connect()
                success = true
            } catch {
                await BarongCalendarClient.shared.writeErrorState(error)
                success = false
            }

            await MainActor.run {
                self.calendarBusy = false
                self.refreshCalendarState()
                self.notchMood = success ? .laugh : .sleepy
                self.heroMessage = success
                    ? "좋아! 이제 일정은 바롱이가 봐줄게"
                    : "연결이 막혔어. 다시 눌러줘"
                self.needsDisplay = true
            }
        }
    }

    private func runCalendarHelper(
        command: String,
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        let nodePath = calendarNodePath
        let helperPath = calendarHelperPath
        let rootPath = projectRootPath

        guard FileManager.default.fileExists(atPath: nodePath),
              FileManager.default.fileExists(atPath: helperPath) else {
            completion?(false)
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: nodePath)
            process.arguments = [helperPath, command]
            process.currentDirectoryURL = URL(fileURLWithPath: rootPath)
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.refreshCalendarState()
                        completion?(process.terminationStatus == 0)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        completion?(false)
                    }
                }
            }
        }
    }

    private var calendarNodePath: String {
        ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
            .first { FileManager.default.fileExists(atPath: $0) } ?? "/opt/homebrew/bin/node"
    }

    private var projectRootPath: String {
        let current = FileManager.default.currentDirectoryPath
        let candidates = [
            URL(fileURLWithPath: current)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .path,
            "/Users/baegyoona/Desktop/해커톤"
        ]

        return candidates.first {
            FileManager.default.fileExists(atPath: "\($0)/scripts/calendar-helper.cjs")
        } ?? candidates[0]
    }

    private var calendarHelperPath: String {
        "\(projectRootPath)/scripts/calendar-helper.cjs"
    }

    private func interpolate(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
        from + ((to - from) * expansion)
    }

    private func drawIslandShell(in rect: NSRect) {
        let topRadius = interpolate(7, 20)
        let bottomRadius = interpolate(15, 28)
        let path = notchAttachedPath(in: rect, topRadius: topRadius, bottomRadius: bottomRadius)

        if expansion > 0.2 {
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 82
            shadow.shadowOffset = NSSize(width: 0, height: -24)
            shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.38 * Double(min(1, (expansion - 0.2) / 0.8)))
            shadow.set()
            NSColor(calibratedWhite: 0, alpha: 0.05).setFill()
            path.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        if expansion > 0.12 {
            NSGraphicsContext.current?.saveGraphicsState()
            path.addClip()
            NSGradient(
                starting: NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.004, alpha: 1),
                ending: NSColor(calibratedRed: 0.086, green: 0.063, blue: 0.067, alpha: 1)
            )?.draw(in: rect, angle: 270)
            NSGraphicsContext.current?.restoreGraphicsState()
        } else {
            NSColor(calibratedWhite: 0.0, alpha: 1.0).setFill()
            path.fill()
        }

        NSColor(calibratedWhite: 1.0, alpha: expansion > 0.12 ? 0.08 : 0.05).setStroke()
        path.lineWidth = expansion > 0.12 ? 1.25 : 1
        path.stroke()
    }

    private func notchAttachedPath(in rect: NSRect, topRadius: CGFloat, bottomRadius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()

        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.curve(
            to: NSPoint(x: rect.maxX - topRadius, y: rect.maxY - topRadius),
            controlPoint1: NSPoint(x: rect.maxX - topRadius * 0.05, y: rect.maxY),
            controlPoint2: NSPoint(x: rect.maxX - topRadius, y: rect.maxY - topRadius * 0.05)
        )
        path.line(to: NSPoint(x: rect.maxX - topRadius, y: rect.minY + bottomRadius))
        path.curve(
            to: NSPoint(x: rect.maxX - topRadius - bottomRadius, y: rect.minY),
            controlPoint1: NSPoint(x: rect.maxX - topRadius, y: rect.minY + bottomRadius * 0.35),
            controlPoint2: NSPoint(x: rect.maxX - topRadius - bottomRadius * 0.35, y: rect.minY)
        )
        path.line(to: NSPoint(x: rect.minX + topRadius + bottomRadius, y: rect.minY))
        path.curve(
            to: NSPoint(x: rect.minX + topRadius, y: rect.minY + bottomRadius),
            controlPoint1: NSPoint(x: rect.minX + topRadius + bottomRadius * 0.35, y: rect.minY),
            controlPoint2: NSPoint(x: rect.minX + topRadius, y: rect.minY + bottomRadius * 0.35)
        )
        path.line(to: NSPoint(x: rect.minX + topRadius, y: rect.maxY - topRadius))
        path.curve(
            to: NSPoint(x: rect.minX, y: rect.maxY),
            controlPoint1: NSPoint(x: rect.minX + topRadius, y: rect.maxY - topRadius * 0.05),
            controlPoint2: NSPoint(x: rect.minX + topRadius * 0.05, y: rect.maxY)
        )
        path.close()

        return path
    }

    private func drawCollapsedBarong(in rect: NSRect, opacity: Double) {
        withAlpha(opacity) {
            let image = currentNotchImage()
            let imageHeight = rect.height + 8
            let imageWidth = imageHeight
            let imageRect = NSRect(
                x: rect.maxX - imageWidth - 17,
                y: rect.minY - 3,
                width: imageWidth,
                height: imageHeight
            )
            image?.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    private func currentNotchImage() -> NSImage? {
        let frames = notchImages(for: notchMood)
        guard !frames.isEmpty else { return nil }

        let frameIndex = Int(CACurrentMediaTime() / 0.42) % frames.count
        return frames[frameIndex]
    }

    private func notchImages(for mood: NotchMood) -> [NSImage] {
        let prefix = mood.resourcePrefix
        if let cached = notchImageCache[prefix] {
            return cached
        }

        let frames = ["A", "B"].compactMap { suffix -> NSImage? in
            guard let url = BarongResources.url(forResource: "\(prefix)\(suffix)", withExtension: "png") else {
                return nil
            }
            return NSImage(contentsOf: url)
        }
        notchImageCache[prefix] = frames
        return frames
    }

    private func drawExpandedContent(in rect: NSRect, opacity: Double) {
        withAlpha(opacity) {
            let horizontalPadding = BarongIslandLayout.horizontalPadding
            let heroY = rect.maxY - BarongIslandLayout.topPadding - BarongIslandLayout.heroHeight - 13 + BarongIslandLayout.contentLift
            let subtitleY = heroY - BarongIslandLayout.heroSubtitleGap - BarongIslandLayout.subtitleHeight
            let heroRect = NSRect(
                x: rect.minX + horizontalPadding,
                y: heroY,
                width: rect.width - (horizontalPadding * 2) - 106,
                height: BarongIslandLayout.heroHeight
            )
            if expansion > 0.78 {
                drawExpandedCat(in: rect, opacity: Double((expansion - 0.78) / 0.22))
            }

            drawText(
                heroMessage,
                in: heroRect,
                font: fittingTalkFont(for: heroMessage, in: heroRect, baseSize: 30, minSize: 18, weight: .heavy),
                color: NSColor(calibratedRed: 1.0, green: 0.89, blue: 0.92, alpha: 1)
            )
            drawText(
                "바롱이랑 함께한지 \(joinedDays)일 째",
                in: NSRect(
                    x: rect.minX + horizontalPadding,
                    y: subtitleY,
                    width: rect.width - (horizontalPadding * 2),
                    height: BarongIslandLayout.subtitleHeight
                ),
                font: BarongFonts.ui(size: 13, weight: .medium),
                color: NSColor(calibratedWhite: 1, alpha: 0.48)
            )

            let zones = expandedHitZones(in: rect)
            drawActionPill(calendarButtonTitle, rect: zones.greeting, filled: false, target: .greeting)
            drawActionPill("츄르 주기", rect: zones.churu, filled: true, target: .churu)
            if !nextMeetings.isEmpty {
                drawMeetingCard(in: zones.meeting, meetings: nextMeetings)
            }
            drawClippedHeartParticles(in: rect)

        }
    }

    private func emitChuruHearts() {
        let zones = expandedHitZones(in: expandedRect)
        let islandRect = expandedRect
        let horizontalPadding = BarongIslandLayout.horizontalPadding
        let now = CACurrentMediaTime()
        let opacities: [CGFloat] = [0.07, 0.04, 0.02]

        let newParticles = (0..<16).map { index in
            HeartParticle(
                startedAt: now + (Double(index) * 0.045),
                duration: Double.random(in: 0.78...1.35),
                start: NSPoint(
                    x: CGFloat.random(in: islandRect.minX + horizontalPadding...islandRect.maxX - horizontalPadding),
                    y: CGFloat.random(in: islandRect.minY + 8...islandRect.minY + 34)
                ),
                rise: CGFloat.random(in: zones.churu.minY - islandRect.minY + 12...zones.churu.maxY - islandRect.minY + 34),
                drift: CGFloat.random(in: -64...64),
                size: randomHeartSize(),
                opacity: opacities.randomElement() ?? 0.05
            )
        }

        heartParticles.append(contentsOf: newParticles)
        startHeartAnimation()
        needsDisplay = true
    }

    private func startHeartAnimation() {
        guard heartTimer == nil else { return }

        heartTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }

                let now = CACurrentMediaTime()
                self.heartParticles.removeAll { now - $0.startedAt > $0.duration }

                if self.heartParticles.isEmpty {
                    self.heartTimer?.invalidate()
                    self.heartTimer = nil
                }

                self.needsDisplay = true
            }
        }

        RunLoop.main.add(heartTimer!, forMode: .common)
    }

    private func drawHeartParticles() {
        let now = CACurrentMediaTime()

        for particle in heartParticles {
            let elapsed = now - particle.startedAt
            guard elapsed >= 0, elapsed <= particle.duration else { continue }

            let rawProgress = CGFloat(elapsed / particle.duration)
            let easedProgress = 1 - pow(1 - rawProgress, 2.6)
            let fade = min(1, (1 - rawProgress) * 1.25)
            let wobble = sin(rawProgress * .pi * 3) * 13
            let point = NSPoint(
                x: particle.start.x + (particle.drift * easedProgress) + wobble,
                y: particle.start.y + (particle.rise * easedProgress)
            )
            let color = NSColor(calibratedWhite: 1, alpha: particle.opacity * max(0, fade))

            drawHeart(center: point, size: particle.size, opacity: color.alphaComponent)
        }
    }

    private func drawClippedHeartParticles(in rect: NSRect) {
        guard !heartParticles.isEmpty else { return }
        guard let context = NSGraphicsContext.current else {
            drawHeartParticles()
            return
        }

        context.saveGraphicsState()
        notchAttachedPath(in: rect, topRadius: 20, bottomRadius: 28).addClip()
        drawHeartParticles()
        context.restoreGraphicsState()
    }

    private func randomHeartSize() -> CGFloat {
        let roll = CGFloat.random(in: 0...1)

        return roll < 0.68
            ? CGFloat.random(in: 42...66)
            : CGFloat.random(in: 72...104)
    }

    private func drawHeart(center: NSPoint, size: CGFloat, opacity: CGFloat) {
        guard let image = heartImage() else { return }

        image.draw(
            in: NSRect(
                x: center.x - size / 2,
                y: center.y - size / 2,
                width: size,
                height: size
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: max(0, min(1, opacity))
        )
    }

    private func heartImage() -> NSImage? {
        if let heartImageCache {
            return heartImageCache
        }

        guard let url = BarongResources.url(forResource: "HeartFill", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        heartImageCache = image
        return image
    }

    private func drawExpandedCat(in rect: NSRect, opacity: Double) {
        let image = currentNotchImage()

        let imageWidth: CGFloat = 94
        let imageHeight: CGFloat = 94
        let imageRect = NSRect(
            x: rect.maxX - BarongIslandLayout.horizontalPadding - imageWidth,
            y: rect.maxY - BarongIslandLayout.topPadding - imageHeight + 8 + BarongIslandLayout.contentLift,
            width: imageWidth,
            height: imageHeight
        )

        image?.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: CGFloat(max(0, min(1, opacity))))
    }

    private func drawMeetingCard(in rect: NSRect, meetings: [BarongCalendarEvent]) {
        guard let firstMeeting = meetings.first else { return }

        let hovered = hoveredTarget == .meeting
        let path = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
        NSColor(calibratedRed: 0.14, green: 0.12, blue: 0.13, alpha: hovered ? 0.98 : 0.94).setFill()
        path.fill()

        if hovered {
            NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.68, alpha: 0.35).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let visibleMeetings = Array(meetings.prefix(2))
        let title = meetingCardTitle(for: firstMeeting, count: visibleMeetings.count)
        let titleFont = BarongFonts.ui(size: 13, weight: .medium)
        let contentX = rect.minX + BarongIslandLayout.meetingPadding
        let contentWidth = rect.width - (BarongIslandLayout.meetingPadding * 2)
        let titleHeight = NSString(string: title).size(withAttributes: [.font: titleFont]).height + 2
        let titleY = rect.maxY - BarongIslandLayout.meetingTopPadding - titleHeight

        drawText(
            title,
            in: NSRect(
                x: contentX,
                y: titleY,
                width: contentWidth,
                height: titleHeight + 2
            ),
                font: titleFont,
                color: NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.68, alpha: 1)
        )

        if visibleMeetings.count == 1 {
            drawSingleMeeting(firstMeeting, in: rect, contentX: contentX, contentWidth: contentWidth, titleY: titleY)
            return
        }

        drawMeetingRows(visibleMeetings, in: rect, contentX: contentX, contentWidth: contentWidth, titleY: titleY)
    }

    private func drawSingleMeeting(
        _ meeting: BarongCalendarEvent,
        in rect: NSRect,
        contentX: CGFloat,
        contentWidth: CGFloat,
        titleY: CGFloat
    ) {
        let mainText = "\(meeting.formattedStartTime) \(meeting.title)"
        let mainRect = NSRect(
            x: contentX,
            y: titleY - 34,
            width: contentWidth,
            height: 28
        )
        let mainFont = fittingUIFont(for: mainText, in: mainRect, baseSize: 20, minSize: 15, weight: .bold)

        drawText(
            mainText,
            in: mainRect,
            font: mainFont,
            color: NSColor(calibratedRed: 1.0, green: 0.9, blue: 0.93, alpha: 0.97)
        )

        guard let location = meeting.location, !location.isEmpty else { return }
        drawText(
            location,
            in: NSRect(
                x: contentX,
                y: rect.minY + BarongIslandLayout.meetingBottomPadding,
                width: contentWidth,
                height: 17
            ),
            font: BarongFonts.ui(size: 12, weight: .medium),
            color: NSColor(calibratedWhite: 1, alpha: 0.54)
        )
    }

    private func drawMeetingRows(
        _ meetings: [BarongCalendarEvent],
        in rect: NSRect,
        contentX: CGFloat,
        contentWidth: CGFloat,
        titleY: CGFloat
    ) {
        let rowHeight: CGFloat = 34
        let rowGap: CGFloat = 8
        let firstRowY = titleY - 12 - rowHeight

        for (index, meeting) in meetings.enumerated() {
            let rowY = firstRowY - (CGFloat(index) * (rowHeight + rowGap))
            let mainText = "\(meeting.formattedStartTime) \(meeting.title)"
            let mainRect = NSRect(
                x: contentX,
                y: rowY + 15,
                width: contentWidth,
                height: 18
            )
            let mainFont = fittingUIFont(for: mainText, in: mainRect, baseSize: 14, minSize: 12, weight: .bold)

            drawText(
                mainText,
                in: mainRect,
                font: mainFont,
                color: NSColor(calibratedRed: 1.0, green: 0.9, blue: 0.93, alpha: index == 0 ? 0.96 : 0.78)
            )

            if let location = meeting.location, !location.isEmpty {
                drawText(
                    location,
                    in: NSRect(
                        x: contentX,
                        y: rowY,
                        width: contentWidth,
                        height: 14
                    ),
                    font: BarongFonts.ui(size: 10.5, weight: .medium),
                    color: NSColor(calibratedWhite: 1, alpha: index == 0 ? 0.48 : 0.36)
                )
            }

            if index == 0 {
                NSColor(calibratedWhite: 1, alpha: 0.07).setStroke()
                let separator = NSBezierPath()
                separator.move(to: NSPoint(x: contentX, y: rowY - (rowGap / 2)))
                separator.line(to: NSPoint(x: contentX + contentWidth, y: rowY - (rowGap / 2)))
                separator.lineWidth = 1
                separator.stroke()
            }
        }
    }

    private func meetingCardTitle(for meeting: BarongCalendarEvent, count: Int) -> String {
        guard let startDate = meeting.startDate else { return "다음 회의" }

        let secondsUntilStart = startDate.timeIntervalSinceNow
        if secondsUntilStart < 0 {
            return "진행 중인 회의"
        }
        if secondsUntilStart <= 600 {
            let minutesLeft = max(1, Int(ceil(secondsUntilStart / 60)))
            return "다음 회의 \(minutesLeft)분 전"
        }
        return count > 1 ? "다음 회의 \(count)개" : "다음 회의"
    }

    private func meetingCardDetail(for meeting: BarongCalendarEvent) -> String {
        let place = meeting.location?.isEmpty == false ? " · \(meeting.location!)" : ""
        return "\(meeting.formattedStartTime) \(meeting.title)\(place)"
    }

    private func drawActionPill(_ title: String, rect: NSRect, filled: Bool, target: ActionTarget) {
        let hovered = hoveredTarget == target
        let drawRect = hovered ? rect.insetBy(dx: -2, dy: -2) : rect
        (filled
            ? NSColor(calibratedRed: 1.0, green: hovered ? 0.62 : 0.56, blue: hovered ? 0.72 : 0.66, alpha: 1)
            : NSColor(calibratedRed: 0.13, green: 0.11, blue: 0.12, alpha: hovered ? 1 : 0.94)
        ).setFill()
        NSBezierPath(roundedRect: drawRect, xRadius: 12, yRadius: 12).fill()

        if hovered {
            NSColor(calibratedRed: 1.0, green: 0.66, blue: 0.76, alpha: filled ? 0.42 : 0.25).setStroke()
            let stroke = NSBezierPath(roundedRect: drawRect, xRadius: 12, yRadius: 12)
            stroke.lineWidth = 1
            stroke.stroke()
        }

        drawCenteredText(
            title,
            in: drawRect,
            font: BarongFonts.ui(size: 14, weight: .bold),
            color: filled
                ? NSColor(calibratedWhite: 0.05, alpha: 1)
                : NSColor(calibratedRed: 1.0, green: 0.9, blue: 0.93, alpha: hovered ? 1 : 0.92)
        )
    }

    private func drawSpeechBubble(at point: NSPoint, text: String) {
        let bubbleRect = NSRect(x: point.x - 10, y: point.y - 7, width: 20, height: 15)
        let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 4, yRadius: 4)
        NSColor(calibratedWhite: 1, alpha: 0.92).setFill()
        bubble.fill()

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bubbleRect.midX - 2, y: bubbleRect.minY + 1))
        tail.line(to: NSPoint(x: bubbleRect.midX + 4, y: bubbleRect.minY - 6))
        tail.line(to: NSPoint(x: bubbleRect.midX + 5, y: bubbleRect.minY + 2))
        tail.close()
        tail.fill()

        drawText(
            text,
            in: bubbleRect.insetBy(dx: 6, dy: 1),
            font: BarongFonts.ui(size: 10, weight: .heavy),
            color: NSColor(calibratedWhite: 0.04, alpha: 1)
        )
    }

    private func drawBarongFace(center: NSPoint, scale: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -32, y: -31)

        NSColor(calibratedRed: 0.72, green: 0.39, blue: 0.13, alpha: 1).setFill()
        NSColor(calibratedWhite: 0.03, alpha: 1).setStroke()

        let leftEar = NSBezierPath()
        leftEar.move(to: NSPoint(x: 16, y: 40))
        leftEar.line(to: NSPoint(x: 23, y: 61))
        leftEar.line(to: NSPoint(x: 32, y: 42))
        leftEar.close()
        leftEar.fill()
        leftEar.stroke()

        let rightEar = NSBezierPath()
        rightEar.move(to: NSPoint(x: 32, y: 42))
        rightEar.line(to: NSPoint(x: 42, y: 61))
        rightEar.line(to: NSPoint(x: 49, y: 40))
        rightEar.close()
        rightEar.fill()
        rightEar.stroke()

        let head = NSBezierPath(roundedRect: NSRect(x: 15, y: 18, width: 36, height: 31), xRadius: 11, yRadius: 11)
        head.lineWidth = 3
        head.fill()
        head.stroke()

        NSColor(calibratedRed: 0.93, green: 0.61, blue: 0.23, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 21, y: 21, width: 25, height: 12)).fill()

        NSColor(calibratedRed: 0.31, green: 0.9, blue: 0.55, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 24, y: 34, width: 6, height: 8)).fill()
        NSBezierPath(ovalIn: NSRect(x: 38, y: 34, width: 6, height: 8)).fill()

        NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 32, y: 27, width: 5, height: 4)).fill()

        context.restoreGState()
    }

    private func drawBarongLounging(center: NSPoint, scale: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: scale, y: scale)

        NSColor(calibratedRed: 0.33, green: 0.16, blue: 0.05, alpha: 0.22).setFill()
        NSBezierPath(ovalIn: NSRect(x: -58, y: -31, width: 126, height: 24)).fill()

        NSColor(calibratedRed: 0.73, green: 0.40, blue: 0.12, alpha: 1).setFill()
        NSColor(calibratedWhite: 0.03, alpha: 0.9).setStroke()

        let body = NSBezierPath(roundedRect: NSRect(x: -18, y: -20, width: 82, height: 42), xRadius: 20, yRadius: 20)
        body.lineWidth = 2
        body.fill()
        body.stroke()

        NSColor(calibratedRed: 0.54, green: 0.27, blue: 0.08, alpha: 0.7).setFill()
        NSBezierPath(roundedRect: NSRect(x: 12, y: -2, width: 42, height: 9), xRadius: 5, yRadius: 5).fill()
        NSBezierPath(roundedRect: NSRect(x: 18, y: 12, width: 28, height: 7), xRadius: 4, yRadius: 4).fill()

        NSColor(calibratedRed: 0.78, green: 0.44, blue: 0.15, alpha: 1).setFill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 58, y: 1))
        tail.curve(to: NSPoint(x: 80, y: 18), controlPoint1: NSPoint(x: 76, y: -5), controlPoint2: NSPoint(x: 87, y: 7))
        tail.curve(to: NSPoint(x: 66, y: 23), controlPoint1: NSPoint(x: 77, y: 25), controlPoint2: NSPoint(x: 70, y: 25))
        tail.curve(to: NSPoint(x: 52, y: 9), controlPoint1: NSPoint(x: 61, y: 20), controlPoint2: NSPoint(x: 56, y: 14))
        tail.close()
        tail.fill()
        tail.stroke()

        drawBarongFace(center: NSPoint(x: -35, y: 9), scale: 0.86)

        NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: -58, y: -23, width: 30, height: 15), xRadius: 7, yRadius: 7).fill()
        NSBezierPath(roundedRect: NSRect(x: -18, y: -25, width: 32, height: 14), xRadius: 7, yRadius: 7).fill()

        context.restoreGState()
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }

    private func drawCenteredText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let textHeight = NSString(string: text).size(withAttributes: attributes).height
        let centeredRect = NSRect(
            x: rect.minX + 12,
            y: rect.midY - (textHeight / 2) - 2,
            width: rect.width - 24,
            height: textHeight + 2
        )

        NSString(string: text).draw(in: centeredRect, withAttributes: attributes)
    }

    private func fittingTalkFont(
        for text: String,
        in rect: NSRect,
        baseSize: CGFloat,
        minSize: CGFloat,
        weight: NSFont.Weight
    ) -> NSFont {
        var size = baseSize

        while size > minSize {
            let font = BarongFonts.talk(size: size, weight: weight)
            let textWidth = NSString(string: text).size(withAttributes: [.font: font]).width
            if textWidth <= rect.width {
                return font
            }
            size -= 1
        }

        return BarongFonts.talk(size: minSize, weight: weight)
    }

    private func fittingUIFont(
        for text: String,
        in rect: NSRect,
        baseSize: CGFloat,
        minSize: CGFloat,
        weight: NSFont.Weight
    ) -> NSFont {
        var size = baseSize

        while size > minSize {
            let font = BarongFonts.ui(size: size, weight: weight)
            let textWidth = NSString(string: text).size(withAttributes: [.font: font]).width
            if textWidth <= rect.width {
                return font
            }
            size -= 1
        }

        return BarongFonts.ui(size: minSize, weight: weight)
    }

    private func withAlpha(_ alpha: Double, draw: () -> Void) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            draw()
            return
        }

        context.saveGState()
        context.setAlpha(CGFloat(max(0, min(1, alpha))))
        draw()
        context.restoreGState()
    }
}
