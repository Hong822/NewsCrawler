# Project: The News Collector (AI-Powered)

## 1. 개요
전 세계 주요 언론사의 뉴스를 사용자가 설정한 검색어와 기간에 맞춰 수집(Collector)하고, AI를 활용해 심층 분석 및 인사이트를 제공하는 플러터(Flutter) 기반 어플리케이션입니다.

## 2. 주요 기능
- **다국어 뉴스 수집**: 한국, 미국, 독일, 영국, 프랑스, 일본, 중국 등 주요 국가 언론사 타겟팅 검색.
- **빈티지 신문 UI**: 뉴욕 타임즈(NYT) 스타일의 디자인 테마와 클래식 타이포그래피 적용.
- **검색 쿼리 가이드**: Lucene 문법(AND, OR, NOT, "", 그룹화 등) 지원 및 i 아이콘을 통한 실시간 도움말 제공.
- **AI Insight 분석**: 수집된 기사를 바탕으로 인사이트 도출 (Gemini, ChatGPT, Claude 지원).
    - 분석 시 참고한 주요 기사(Primary Sources) 하이퍼링크 자동 생성.
    - 분석 중 중단(STOP) 및 질문 수정(EDIT PROMPT) 기능.
    - AI 분석 버튼을 파란색으로 강조하여 사용성 개선.
- **스마트 로그 패널**: 
    - 실시간 실행 로그 제공 및 자동 스크롤(Auto-scroll) 지원.
    - 사용자 조작 감지 시 자동 스크롤 중지 및 'SCROLL TO BOTTOM' 플로팅 버튼 제공.
- **검색 모드 분리**:
    - **Simple Search**: 최신 헤드라인 중심의 빠른 검색.
    - **Detail Search**: 키워드 및 날짜 구간 분할을 통한 정밀/심층 수집.
- **커스텀 날짜 선택**: 숫자 자동 구분자 삽입 및 주말 색상이 적용된 직관적인 Date Picker.
- **수익화 모델**: 하단 배너 광고 및 검색 완료 후 전면 광고(Interstitial Ad) 적용.
- **보안 및 관리**: 사용자가 직접 자신의 API Key를 관리하며, 각 서비스별 발급 가이드 링크 제공.

## 3. 기술 스택
- **AI**: Google Generative AI, OpenAI, Anthropic API
- **Ad Engine**: Google Mobile Ads (AdMob)
- **Data Source**: Direct RSS Feed & Google News RSS Fallback (Scraping)
- **Key Libraries**:
    - `google_fonts`: 클래식 타이포그래피 구현
    - `google_mobile_ads`: 전면 및 배너 광고 구현
    - `firebase_core`, `cloud_functions`: Firebase 연동 및 서버 로직 처리
    - `http`: RSS 및 번역 데이터 요청 (UTF-8 디코딩 처리)
    - `xml`: RSS/Atom 데이터 파싱
    - `intl`: 다국어 및 날짜 포맷팅
    - `shared_preferences`: 검색/질문 히스토리 및 API Key 로컬 저장
