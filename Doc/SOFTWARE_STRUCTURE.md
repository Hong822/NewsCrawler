# Software Structure & Architecture

## 1. Directory Structure
```text
news_crawler/
├── Doc/                      # 개발 및 아키텍처 문서
├── assets/
│   ├── news_sources.json     # 6개국 언론사 마스터 메타데이터
│   └── api_key.txt           # Gemini API Key (git 제외)
├── lib/
│   ├── main.dart             # UI, 상태 관리, 주기적 실행 로직
│   ├── firebase_options.dart # Firebase 플랫폼별 설정 (자동 생성)
│   └── news_crawler_service.dart # 크롤링 엔진 및 번역/메일 서비스
├── functions/                # Firebase Cloud Functions (Node.js)
│   ├── index.js              # RSS Proxy 및 Email 발송 로직
│   └── package.json
└── pubspec.yaml              # 의존성 및 에셋 설정
```

## 2. 핵심 로직 흐름 (Data Flow)
1. **Init**: `main.dart`에서 언론사 JSON과 API Key 로드.
2. **Input**: 사용자가 검색어 입력 및 언론사/기간 선택.
3. **Crawl Start**: `NewsCrawlerService.crawl()` 호출.
    - `_translateManual`: 검색어가 한국어가 아니면 Google Translate API로 해당국가 언어 번역.
    - `_crawlSingleSource`: 각 언론사별로 병렬 실행.
        - 웹(Web) 환경: Firebase Cloud Functions (`fetchRssData`)를 통해 CORS 우회 및 UTF-8 인코딩 보장.
        - PC/모바일: 직접 HTTP GET 요청 (바이트 단위 수신 후 UTF-8 디코딩).
        - `_checkMatch`: 획득된 기사 제목을 논리 연산자(AND/OR/&&/||) 기반으로 필터링.
    - `getAIInsight`: 수집된 기사 데이터를 AI(Gemini)에 전달하여 분석.
        - 503 서버 부하 발생 시 자동 재시도(Retry) 메커니즘 작동.
        - 분석 과정의 로그를 UI(AI Insight Card)에 실시간 출력.
        - 분석 답변 내 참고 기사 번호를 추출하여 클릭 가능한 링크 섹션 생성.
        - 로그 출력: `[순번] (언론사) 제목 - [일치/불일치]`.
4. **Translate**: 수집된 외국어 제목들을 `_batchTranslateTitles`를 통해 한국어로 일괄 번역.
5. **Output**: UI 업데이트 및 기사 클릭 시 브라우저 연동.

## 3. 주요 클래스 정의
### `NewsArticle`
- 기사 정보를 담는 데이터 모델 (`title`, `originalTitle`, `url`, `source`, `pubDate`).

### `NewsCrawlerService`
- `crawl()`: 전체 크롤링 프로세스 제어.
- `getAIInsight()`: Gemini API 연동 및 분석 결과 도출.
- `fetchGeminiModels()`: (Optional) Google AI API에서 지원 가능한 최신 Gemini 모델 목록을 실시간으로 조회하는 기능.
- `_checkMatch()`: 제목과 검색어의 일치 여부 판별 (Case-insensitive, Logical operators).
- `sendEmail()`: Firebase Cloud Functions (`sendNewsEmail`)를 호출하여 Nodemailer로 메일 발송.

## 4. UI 및 텍스트 기술
- **Typography**: `google_fonts` 패키지를 사용한 `UnifrakturMaguntia`, `Playfair Display`, `Libre Baskerville` 조합.
- **Text Interaction**: `SelectionArea`를 통한 리스트 및 로그 텍스트 선택/복사 기능.
- **Responsiveness**: 화면 너비 600px 기준 모바일/데스크톱 레이아웃 자동 전환.
- **Link Tracking**: `_visitedUrls` (Set)를 이용한 방문 기사 색상 변경 (Blue -> Purple).
