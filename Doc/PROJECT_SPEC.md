# Project: News Crawler (AI-Powered)

## 1. 개요
전 세계 주요 언론사의 뉴스를 사용자가 설정한 검색어와 기간에 맞춰 크롤링하고, 외국어 헤드라인을 한국어로 번역하여 리포팅하는 플러터(Flutter) 기반 어플리케이션입니다.

## 2. 주요 기능
- **다국어 크롤링**: 한국, 미국, 일본, 독일, 영국, 중국 6개국의 주요 언론사 도메인 타겟팅 검색.
- **논리 연산자 검색**: 검색어 내 `and`, `or`, `&&`, `||` 등 표준 검색 문법 지원 및 자체 필터링 엔진.
- **번역 엔진**: Google Translate HTTP API (`_translateManual`)를 통한 키워드 및 헤드라인 번역.
- **Firebase 연합**:
    - **Hosting**: 웹 버전 배포 및 서비스 호스팅.
    - **Cloud Functions**: 웹 브라우저 CORS 제한 우회(RSS Proxy) 및 Nodemailer 기반 서버사이드 이메일 발송.
- **검색 히스토리**: `shared_preferences`를 이용한 최근 검색어 저장 및 자동완성(Autocomplete) UI.
- **리포트 전송**: 수집된 뉴스 리스트를 시스템 메일 앱(`mailto:`)을 통해 전송.
- **실행 모드**: 즉시 실행(Run Once) 및 주기적 실행(Periodic Run, 현재 5분 주기).

## 3. 기술 스택
- **Framework**: Flutter (Dart) - Web, Windows, Android 지원
- **Backend**: Firebase (Hosting, Cloud Functions)
- **Data Source**: Direct RSS Feed & Google News RSS Fallback
- **Key Libraries**:
    - `firebase_core`, `cloud_functions`: Firebase 연동
    - `http`: RSS 데이터 요청
    - `xml`: RSS 데이터 파싱
    - `url_launcher`: 기사 본문 호출
    - `shared_preferences`: 로컬 데이터 저장
