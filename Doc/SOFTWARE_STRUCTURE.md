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
        - 웹(Web) 환경: Firebase Cloud Functions (`fetchRssData`)를 통해 CORS 우회.
        - PC/모바일: 직접 HTTP GET 요청.
        - `_checkMatch`: 획득된 기사 제목을 논리 연산자(AND/OR/&&/||) 기반으로 필터링.
        - 로그 출력: `[순번] (언론사) 제목 - [일치/불일치]`.
4. **Translate**: 수집된 외국어 제목들을 `_batchTranslateTitles`를 통해 한국어로 일괄 번역.
5. **Output**: UI 업데이트 및 기사 클릭 시 브라우저 연동.

## 3. 주요 클래스 정의
### `NewsArticle`
- 기사 정보를 담는 데이터 모델 (`title`, `originalTitle`, `url`, `source`, `pubDate`).

### `NewsCrawlerService`
- `crawl()`: 전체 크롤링 프로세스 제어.
- `_checkMatch()`: 제목과 검색어의 일치 여부 판별 (Case-insensitive, Logical operators).
- `sendEmail()`: Firebase Cloud Functions (`sendNewsEmail`)를 호출하여 Nodemailer로 메일 발송.

## 4. 번역 및 외부 서비스
- **Translation**: Google Translate HTTP API (client=gtx) 사용.
- **Backend**: Firebase Cloud Functions (Node.js 20)
- **Windows Build Options**:
    - `CMAKE_POLICY_VERSION_MINIMUM 3.10` 설정 필수 (Firebase SDK 호환성).
    - 아이콘 빌드 에러 시 `--no-tree-shake-icons` 옵션 사용.
