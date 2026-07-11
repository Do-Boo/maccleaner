# MacCleaner

SwiftUI로 만든 네이티브 macOS 정리 및 시스템 관리 앱과 iPhone용 동반 앱입니다.

## Homebrew 설치

```bash
brew install --cask do-boo/maccleaner/maccleaner
```

설치 후 응용 프로그램 폴더에서 `MacCleaner`를 실행합니다. 현재 공개 빌드는 Apple 공증 전 개발 버전이며, Homebrew cask가 설치 과정에서 앱의 다운로드 격리 속성을 제거합니다. 소스와 SHA-256이 공개되어 있으므로 설치 전에 내용을 검토할 수 있습니다.

제거:

```bash
brew uninstall --cask do-boo/maccleaner/maccleaner
```

## 기능

**대시보드 & 스마트 스캔**
- 디스크·메모리 사용량 확인, 메모리 해제(purge), 휴지통 비우기, 로그인 시 자동 시작
- **스마트 스캔** — 버튼 하나로 시스템 정리 + 오래된 다운로드 + 브라우저 캐시를 스캔하고 원클릭 정리

**메뉴바 실시간 모니터**
- 메뉴바에 CPU·메모리 사용률 상시 표시 (2초 간격 갱신)
- 클릭하면 CPU/메모리 게이지, 디스크 여유 공간, 네트워크 ↓↑ 속도, CPU 상위 프로세스 5개 표시
- 메인 창을 닫아도 메뉴바에 계속 동작

**정리**
- **시스템 정리** — 사용자 캐시, 로그, Xcode 데이터, 메일 첨부파일 스캔 후 선택 삭제
- **대용량 파일** — 홈 폴더에서 100MB~5GB 이상 파일 탐색
- **중복 파일** — 내용이 완전히 같은 파일을 SHA-256 해시로 찾아 정리
- **다운로드 정리** — 다운로드 폴더에서 1개월~1년 이상 방치된 항목 정리

**앱**
- **앱 관리** — 앱과 잔여 파일(설정, 캐시, 컨테이너 등)까지 한 번에 삭제
- **업데이터** — Homebrew로 설치한 앱·도구의 업데이트 확인 및 업그레이드

**속도**
- **시작 프로그램** — 로그인 시 자동 실행되는 LaunchAgent 켜기/끄기
- **유지보수** — 메모리 해제, DNS 캐시 초기화, Spotlight 재색인, Finder/Dock 재실행 등

**보안**
- **개인정보** — 브라우저(Safari/Chrome/Edge/Brave/Firefox/웨일) 캐시·방문 기록·쿠키 정리
- **셰레더** — 파일을 무작위 데이터로 덮어쓴 뒤 삭제 (복구 불가)

> 안전 장치: 모든 삭제는 영구 삭제가 아니라 **휴지통으로 이동**입니다.
> 실수로 지워도 휴지통에서 복원할 수 있습니다. (휴지통 비우기만 예외)

## 실행 방법

### 개발 모드로 바로 실행

```bash
swift run
```

### 범용 .app 만들기 (Apple Silicon + Intel)

```bash
./build-app.sh
open build/MacCleaner.app
```

만든 앱을 계속 쓰려면 `build/MacCleaner.app`을 응용 프로그램 폴더로 옮기면 됩니다.

### 릴리스 ZIP 만들기

```bash
./Scripts/package-release.sh 1.0.0
```

`release/MacCleaner-1.0.0.zip`과 Homebrew cask에 사용할 SHA-256 체크섬이 생성됩니다.

## 요구 사항

- macOS 14 (Sonoma) 이상
- Swift 5.10 이상 (Xcode Command Line Tools)

## iPhone 앱

`Mobile/MacCleanerMobile.xcodeproj`에는 iOS 17 이상에서 실행되는 별도 앱이 포함되어 있습니다.

- 기기 전체·여유 저장 공간, 배터리, 네트워크 상태 확인
- 사진 보관함의 스크린샷, 60초 이상 동영상, 유사 촬영 후보 분류
- 사용자가 선택한 사진과 동영상을 iOS의 최근 삭제된 항목으로 이동
- 파일 앱에서 여러 파일을 가져와 크기 확인, 공유, 앱 보관함에서 삭제

```bash
cd Mobile
xcodegen generate
open MacCleanerMobile.xcodeproj
```

> iOS 샌드박스 정책상 다른 앱의 캐시, 시스템 로그, 앱 데이터는 조회하거나 삭제할 수 없습니다. 모바일 앱은 사용자가 권한을 부여한 사진과 앱으로 직접 가져온 파일만 변경합니다.

## 프로젝트 구조

```
Sources/MacCleaner/
├── MacCleanerApp.swift        # 앱 진입점
├── Models.swift               # 공용 데이터 모델
├── Scanners.swift             # 캐시/로그/대용량/앱/시스템 상태 스캔·삭제 로직
├── Shell.swift                # 셸 명령·관리자 권한 실행 헬퍼
├── ViewModels.swift           # 대시보드/정리/대용량/앱 화면 상태
├── ContentView.swift          # 사이드바 네비게이션
├── DashboardView.swift        # 대시보드
├── JunkView.swift             # 시스템 정리
├── LargeFilesView.swift       # 대용량 파일
├── AppsView.swift             # 앱 관리
├── DuplicatesFeature.swift    # 중복 파일 (스캐너+화면)
├── DownloadsFeature.swift     # 다운로드 정리
├── LoginItemsFeature.swift    # 시작 프로그램
├── MaintenanceFeature.swift   # 유지보수 도구
├── PrivacyFeature.swift       # 브라우저 개인정보 정리
├── ShredderFeature.swift      # 셰레더
├── UpdaterFeature.swift       # Homebrew 업데이터
├── SmartScanFeature.swift     # 스마트 스캔 (원클릭 정리)
└── MonitorFeature.swift       # 메뉴바 실시간 모니터 (CPU/메모리/네트워크)
```

## 참고

- 처음 스캔 시 macOS가 폴더 접근 권한(문서, 다운로드 등)을 물어볼 수 있습니다. 허용해야 스캔이 됩니다.
- "휴지통 비우기"는 Finder 자동화 권한이 필요합니다 (시스템 설정 > 개인정보 보호 및 보안 > 자동화).
- "메모리 해제", "DNS 캐시 초기화", "Spotlight 재색인"은 관리자 암호를 물어봅니다.
- Safari의 방문 기록·캐시 정리는 "전체 디스크 접근 권한"이 필요할 수 있습니다.
- 셰레더를 제외한 모든 삭제는 휴지통 이동이라 복원 가능합니다.
