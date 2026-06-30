# 바롱이

바롱이는 맥북 노치에 사는 업무 반려펫입니다. Notchi처럼 노치/메뉴바 영역에 붙어 있다가, 누르면 바롱이 아일랜드가 펼쳐지는 macOS 네이티브 앱을 목표로 합니다.

## 제품 방향

- 실제 앱: SwiftUI + AppKit NSPanel 기반 macOS 네이티브 앱
- 랜딩페이지: React/Vite 웹 페이지
- 이전 Electron 구현: UI/흐름 확인용 프로토타입

## 목표 경험

1. 앱이 실행되면 바롱이가 맥북 노치에 붙어 있음
2. 노치/바롱이를 누르면 아래로 바롱이 아일랜드가 확장됨
3. 첫 실행에서 Google Calendar를 연결함
4. 회의 10분 전에 바롱이가 알림을 보여줌
5. 츄르주기/밥주기로 출근과 퇴근을 체크함

## 네이티브 바롱이 앱 실행

```bash
cd native/BarongNotch
swift run BarongNotch
```

이 버전이 최종 방향의 본체입니다. macOS 상단 노치/메뉴바 영역에 `NSPanel`을 띄우고, 클릭 시 아래로 확장됩니다.

## 현재 웹 프로토타입 실행

```bash
bun install
bun run dev
```

## 현재 Electron 프로토타입 실행

Electron 버전은 최종 방향이 아니라 참고용입니다.

```bash
bun run dev:app
```

## Google Calendar 연동

현재 Google OAuth 로그인과 Calendar API 조회는 네이티브 노치 앱 안에서 처리합니다. 앱을 설치한 사람마다 자기 Google 계정으로 로그인하고, 토큰은 각자의 Mac 안에만 저장됩니다.

1. Google Cloud Console에서 Calendar API를 켜고 OAuth 데스크톱 클라이언트를 만듭니다.
2. 프로젝트 루트에 `.env.local`을 만들고 아래 값을 넣습니다.

```bash
GOOGLE_CLIENT_ID="..."
GOOGLE_CLIENT_SECRET="..."
```

3. `cd native/BarongNotch && swift run BarongNotch`로 앱을 실행합니다.
4. 아일랜드에서 `캘린더 연결`을 누르고 Google 로그인을 완료합니다.
5. 남은 일정이 있을 때만 네이티브 아일랜드에 일정 카드가 표시됩니다.

## 배포 파일 만들기

```bash
bun run build:release
```

배포용 ZIP은 아래 경로에 만들어집니다.

```text
public/downloads/barong-notch-macos.zip
dist/downloads/barong-notch-macos.zip
```

ZIP에는 앱 공용 OAuth 설정만 포함됩니다. 개인 Google Calendar 토큰은 `~/Library/Application Support/barong/google-calendar-token.json`에 저장되며 배포 파일에 포함하지 않습니다.

## 문서

PRD: [docs/barong-prd.md](docs/barong-prd.md)
