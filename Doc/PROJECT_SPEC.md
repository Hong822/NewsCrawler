# Project: News Crawler (AI-Powered)

## 1. 개요
전 세계 주요 언론사의 뉴스를 사용자가 설정한 검색어와 기간에 맞춰 크롤링하고, 외국어 헤드라인을 한국어로 번역하여 리포팅하는 플러터(Flutter) 기반 어플리케이션입니다.

## 2. 주요 기능
- **다국어 크롤링**: 한국, 미국, 일본, 독일, 영국, 중국 6개국의 주요 언론사 도메인 타겟팅 검색.
- **논리 연산자 검색**: 검색어 내 `and`, `or`, `&&`, `||` 등 표준 검색 문법 지원 및 자체 필터링 엔진.
- **AI 번역 (Google Gemini)**: 외국어 검색어의 현지어 번역 및 수집된 결과의 한국어 일괄 번역.
- **검색 히스토리**: `shared_preferences`를 이용한 최근 검색어 저장 및 자동완성(Autocomplete) UI.
- **리포트 전송**: 수집된 뉴스 리스트를 시스템 메일 앱(`mailto:`)을 통해 전송.
- **실행 모드**: 즉시 실행(Run Once) 및 주기적 실행(Periodic Run, 현재 5분 주기).

## 3. 기술 스택
- **Framework**: Flutter (Dart)
- **AI**: Google Generative AI (Gemini 1.5 Flash)
- **Data Source**: Google News RSS (Search Engine)
- **Key Libraries**:
    - `http`: RSS 데이터 요청
    - `xml`: RSS 데이터 파싱
    - `html`: HTML 엔티티 정제
    - `url_launcher`: 기사 본문 및 메일 앱 호출
    - `shared_preferences`: 로컬 데이터 저장
