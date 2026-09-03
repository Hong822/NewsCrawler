# Project: News Crawler (AI-Powered)

## 1. 개요
전 세계 주요 언론사의 뉴스를 사용자가 설정한 검색어와 기간에 맞춰 크롤링하고, 외국어 헤드라인을 한국어로 번역하여 리포팅하는 플러터(Flutter) 기반 어플리케이션입니다.

## 2. 주요 기능
- **다국어 크롤링**: 한국, 미국, 독일, 영국, 프랑스, 일본, 중국 7개국의 주요 언론사 도메인 타겟팅 검색.
- **빈티지 신문 UI**: 뉴욕 타임즈(NYT) 스타일의 종이 질감 배경과 클래식 폰트(`Playfair Display`, `Libre Baskerville`, `UnifrakturMaguntia`) 적용.
- **AI Insight Summary**: Gemini 3.6 Flash를 이용한 수집 기사 심층 분석 및 비즈니스 인사이트 도출. 분석 시 참고한 주요 기사(Primary Sources)의 하이퍼링크 자동 생성.
- **텍스트 복사 지원**: 결과창 및 로그 창의 모든 텍스트를 마우스 드래그 및 우클릭으로 복사 가능.
- **실행 모드**: 단일/주기적 실행 지원 및 AI 분석 포함 여부 선택 가능 (4가지 모드).

## 3. 기술 스택
- **AI**: Google Generative AI (Gemini 3.6 Flash)
- **Data Source**: Direct RSS Feed & Google News RSS Fallback
- **Key Libraries**:
    - `google_fonts`: 클래식 타이포그래피 구현
    - `firebase_core`, `cloud_functions`: Firebase 연동
    - `http`: RSS 및 번역 데이터 요청 (UTF-8 강제 디코딩)
    - `xml`: RSS 데이터 파싱
    - `url_launcher`: 기사 본문 호출
    - `shared_preferences`: 검색/이메일/AI 질문 히스토리 저장
