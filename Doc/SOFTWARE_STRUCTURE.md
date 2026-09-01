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
│   └── news_crawler_service.dart # 크롤링 엔진 및 AI 서비스
└── pubspec.yaml              # 의존성 및 에셋 설정
```

## 2. 핵심 로직 흐름 (Data Flow)
1. **Init**: `main.dart`에서 언론사 JSON과 API Key 로드.
2. **Input**: 사용자가 검색어 입력 및 언론사/기간 선택.
3. **Crawl Start**: `NewsCrawlerService.crawl()` 호출.
    - `_translateQuery`: 검색어가 한국어가 아니면 AI로 해당국가 언어 번역.
    - `_crawlSingleSource`: 각 언론사별로 병렬 실행.
        - `site:domain` 연산자를 사용해 RSS 피드 획득.
        - `_checkMatch`: 획득된 기사 제목을 논리 연산자(AND/OR) 기반으로 필터링.
        - 로그 출력: `[순번] (언론사) 제목 - [일치/불일치]`.
4. **Translate**: 수집된 외국어 제목들을 `_batchTranslateTitles`를 통해 한국어로 일괄 번역.
5. **Output**: UI 업데이트 및 기사 클릭 시 브라우저 연동.

## 3. 주요 클래스 정의
### `NewsArticle`
- 기사 정보를 담는 데이터 모델 (`title`, `originalTitle`, `url`, `source`, `pubDate`).

### `NewsCrawlerService`
- `GenerativeModel`: Gemini AI 연동 객체.
- `crawl()`: 전체 크롤링 프로세스 제어.
- `_checkMatch()`: 제목과 검색어의 일치 여부 판별 (Case-insensitive, Logical operators).
- `sendEmail()`: `mailto:` 프로토콜 기반 이메일 본문 생성 및 호출.

## 4. AI 모델 상세
- **Model**: `gemini-1.5-flash`
- **Usage**:
    - 검색 키워드 현지어 번역 (ko -> en, ja, zh-CN, de).
    - 수집된 헤드라인 리스트를 한국어로 일괄 번역하여 일관된 경험 제공.
