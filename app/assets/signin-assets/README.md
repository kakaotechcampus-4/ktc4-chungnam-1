# 구글 로그인 버튼 이미지

구글이 배포한 "Sign in with Google" 버튼 이미지다. 직접 그리지 않고 배포본을
그대로 쓴다. 색, 비율과 여백을 바꾸지 않는다.

| 항목 | 값 |
| --- | --- |
| 출처 | Google Identity 브랜드 자산 묶음 `signin-assets.zip` |
| 받은 곳 | <https://developers.google.com/identity/branding-guidelines> |
| 조건 | 위 브랜딩 가이드라인을 따르는 범위에서 사용한다 |

## 남긴 파일

    Android/png@4x/light/android_light_rd_na@4x.png

앱이 쓰는 하나다. `lib/features/auth/google_sign_in_button.dart` 가 참조하고
`pubspec.yaml` 에 이 경로만 선언한다.

원본 묶음에는 Android, iOS 와 Web 용으로 색(light, dark, neutral), 모양(사각,
둥근 사각, 원형)과 크기별 변형 360개가 함께 들어 있다. 쓰지 않는 359개는
저장소에서 뺐다(PR #50 리뷰). 앱에 다크 테마가 없어 dark 변형도 두지 않았다.

다른 변형이 필요해지면 위 주소에서 다시 받아 쓰는 것만 추가한다. 묶음을
통째로 넣지 않는다.
