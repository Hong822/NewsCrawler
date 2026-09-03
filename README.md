# News Crawler (AI-Powered)

멀티 국가 뉴스 크롤링 및 번역 리포팅 어플리케이션

## 주요 기능
- **7개국 뉴스 검색**: KR, US, DE, UK, FR, JP, CN 주요 언론사 타겟팅.
- **빈티지 신문 디자인**: 뉴욕 타임즈 스타일의 클래식한 UI와 타이포그래피.
- **AI 분석 (Gemini 3.6)**: 수집된 뉴스를 기반으로 한 비즈니스 인사이트 도출 및 참고 문헌 링크 생성.
- **논리 연산자 지원**: `AND`, `OR`, `&&`, `||`를 사용한 정교한 키워드 필터링.
- **자동 번역**: Google Translate API를 이용한 키워드 현지어 번역 및 헤드라인 한국어 번역.
- **멀티 플랫폼**: Web, Windows, Android 지원.
- **Firebase 통합**: 
  - CORS 우회를 위한 Proxy Functions.
  - Nodemailer 기반 이메일 리포트 발송.
  - Firebase Hosting을 통한 웹 배포.

## 설치 및 실행

### Prerequisites
- Flutter SDK
- Node.js (Functions 배포용)
- Firebase CLI (`npm install -g firebase-tools`)

### Setup
1. 의존성 설치:
   ```bash
   flutter pub get
   cd functions && npm install && cd ..
   ```
2. Firebase 설정:
   ```bash
   flutterfire configure --project=YOUR_PROJECT_ID
   ```
3. Firebase Functions 배포:
   ```bash
   firebase deploy --only functions
   ```

### Build & Run
- **Debug Run**: `flutter run -d windows`
- **Windows Build**: `flutter build windows --no-tree-shake-icons`
- **Web Deploy**: `flutter build web && firebase deploy --only hosting`

## 문서
- [Project Specification](Doc/PROJECT_SPEC.md)
- [Software Structure](Doc/SOFTWARE_STRUCTURE.md)
