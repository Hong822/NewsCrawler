# Software Structure & Architecture

## 1. Directory Structure
```text
news_collector/
├── Doc/                      # 개발 및 아키텍처 문서
├── assets/
│   └── news_sources.json     # 주요 언론사 마스터 메타데이터
├── lib/
│   ├── main.dart             # UI(Stateful), 광고 관리, 히스토리 로직
│   ├── news_collector_service.dart # 크롤링 엔진 (Batch/Date splitting)
│   ├── ad_helper.dart        # AdMob ID 및 광고 플랫폼 관리
│   └── firebase_options.dart # Firebase 플랫폼별 설정 (자동 생성)
├── functions/                # Firebase Cloud Functions (Node.js)
│   ├── index.js              # RSS Proxy 및 Email 발송 로직
│   └── package.json
└── pubspec.yaml              # 의존성 설정 (Google Mobile Ads, AI SDKs 등)
```

## 2. 핵심 로직 흐름 (Data Flow)
1. **Init**: `main.dart`에서 언론사 데이터 로드 및 광고(배너/전면) 초기화.
2. **Search**:
    - **Simple**: 단일 쿼리로 빠른 수집.
    - **Detail**: 키워드 3개 단위 Batch 처리 및 날짜 구간(최대 12개) 분할 수집.
    - `_crawlSingleSource`: 각 언론사별 RSS 직접 요청 또는 Google News Fallback 수행.
3. **Ads**: 크롤링 완료 후 결과 출력 전 **전면 광고(Interstitial Ad)** 송출.
4. **AI Analysis**: 
    - 결과창 상단 통합 섹션에서 수동 트리거.
    - `getAIInsight`: Gemini/ChatGPT/Claude를 통한 문서 요약 및 분석.
    - 중단(STOP) 신호 발생 시 비동기 루프 즉시 종료.
5. **UI Update**: `FittedBox` 및 `Shrink` 로직을 통한 가변 해상도 대응 및 텍스트 오버플로우 방지.

## 3. 주요 모듈 설명
### `NewsCollectorService`
- **Query Splitting**: `OR` 연산자로 구분된 긴 검색어를 3개씩 쪼개어 수집 밀도 향상.
- **Date Range Splitting**: 긴 기간(1년 등) 검색 시 날짜 구간을 분할하여 구글 뉴스 응답 제한(100개) 극복.
- **Duplicate Removal**: URL 해시 기반 실시간 중복 기사 제거.

### `main.dart` (UI/UX)
- **DateInputFormatter**: 숫자만 입력해도 `mm/dd/yyyy` 형식이 완성되는 자동 포맷터.
- **Search Query Guide**: `Icons.info_outline` 버튼을 통해 Lucene 검색 문법 다이얼로그 호출.
- **Smart Log Panel**: `NotificationListener`를 통해 사용자 스크롤을 감지하여 `Auto Scroll` 여부를 동적으로 결정.
- **AI Setting**: 각 AI 제공자별 API 발급 가이드 팝업 및 외부 링크 연동 (UI 명칭을 'AI SETTING'으로 통일).

## 4. 디자인 및 스타일
- **Theme**: 신문 스타일의 `F4F1EA` (종이색) 배경과 `Black` 강조색 사용.
- **Link Tracking**: `_visitedUrls` (Set)를 이용해 방문한 기사 색상 변경 (Blue -> Purple).
- **Responsive Layout**: `LayoutBuilder`를 이용한 Mobile/Desktop 전용 레이아웃 분기.
