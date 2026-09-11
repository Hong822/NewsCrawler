# [Flutter] 기본 보호 규칙
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# [Google Mobile Ads] AdMob 안전 설정
# 광고 SDK의 모든 클래스와 인터페이스를 보존하여 광고 로드 실패를 방지합니다.
-keep public class com.google.android.gms.ads.** { public *; }
-keep public class com.google.ads.** { public *; }
-keep class com.google.android.gms.internal.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# [Firebase] Firebase 관련 안전 설정
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# [Networking & JSON] HTTP, Gemini, OpenAI 관련
# 제네릭 타입 정보와 애노테이션을 유지하여 JSON 파싱 에러를 방지합니다.
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses
-keepattributes SourceFile, LineNumberTable

# OkHttp, Okio (네트워크 라이브러리) 경고 무시
-dontwarn okio.**
-dontwarn com.squareup.okhttp.**
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**

# [AndroidX] 시스템 라이브러리 보호
-keep class androidx.** { *; }
-dontwarn androidx.**

# [Custom Models] 만약 Java/Kotlin으로 작성된 데이터 모델이 있다면 보호가 필요합니다.
# (Flutter 위주 프로젝트라면 위 설정들로 충분합니다.)
