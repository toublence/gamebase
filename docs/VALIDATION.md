# Validation — 2026-09-30

검증 엔진: **4.7.2.stable.official.ed1daf0bf**, macOS, headless.

- 정적 리소스 참조 경로, 9개 locale의 공통 48개 key 일치: 통과.
- project.godot / Android Debug·Release preset / 테스트 export 제외 설정: 확인.
- Godot editor asset import 실행. 초기 import에서 발견한 예약어 충돌과 Variant 타입 추론을 수정하고 오디오 설정 리소스를 런타임 로딩으로 변경.
- 이어서 실제 headless verification Scene 실행: **BASE_VERIFY: 51 checks, 0 failures**, 종료 코드 0, 해당 실행의 script/runtime error 없음.
- 저장: 새 파일, 영속성, JSON 확장 데이터, 잘못된 타입, backup 복구, v1→v2 migration, future schema 쓰기 차단.
- 흐름: Boot→Menu→Host→Pause/Settings→Result→Replay→Menu, 중복 전환 차단, background pause/foreground 수동 resume.
- Audio: Master/Music/SFX 설정 반영, optional null stream 처리.
- Haptic: desktop no-op 호출. 실제 기기 진동은 검증하지 않음.
- Ads: 미준비 rewarded callback(false), active gameplay interstitial 거부. native SDK 호출은 검증하지 않음.
- Localization: 9개 언어 실제 로딩, Arabic RTL flag.
- UI: 세 화면 크기에서 Menu 논리 폭 확인. 이후 SafeArea의 실제 좌우 inset을 폭 계산에 포함하도록 보완했으며, 추가 테스트 실행은 하지 않음. notch·회전·터치·폰트·스크롤의 시각적 검수는 실기기 대상.

별도 검증 경로는 `user://verification/`이며 프로덕션 저장 파일을 건드리지 않았습니다. 전체 빌드나 반복 테스트를 실행하지 않았습니다. 검증 스크립트는 필요한 경우 `python3 tools/verify.py`로 재사용할 수 있습니다.

## Android 환경

설치된 Godot Android debug APK template의 manifest: min SDK 24, target/compile SDK 36. JDK 17, Android SDK 36, build-tools 36, debug/release APK template 존재 확인. 프리셋도 min 24 / target 36으로 구성.

APK/AAB 생성·기기 설치·실기기 테스트는 수행하지 않았습니다. 현재 export template 폴더에는 Gradle build용 android_source.zip이 없으므로 Release AAB에는 일치하는 build template 설치와 release signing 설정이 필요합니다. AdMob/Firebase native SDK는 설치·연결되지 않았습니다.

## 출시 전 파생 게임에서 확인

실제 Android 기기의 safe area/시스템 내비게이션/가로·세로/태블릿, pointer 취소/멀티터치, lifecycle/강제 종료, 음량·진동, CJK/Arabic glyph, 저사양 60fps와 메모리, package/app name/user data directory 분리, release signing/AAB, native 광고·UMP·Analytics 통합. 이 보고서는 상용 스토어 제출 인증이나 native 기기 테스트 결과가 아닙니다.

## 2026-10-01 수정 (Blockory 제작 중 발견)

- **Android Debug 내보내기 불가 수정**: Gradle 빌드가 꺼진 Debug 프리셋이 min/target SDK를 덮어써 Godot가 내보내기를 거부했습니다. Debug 프리셋은 SDK를 비우고(템플릿 값 24/36 사용) Release(Gradle)만 지정합니다. `tools/verify.py`가 이 규칙을 검사합니다.
- **ETC2/ASTC import 활성화**: Android 내보내기의 필수 설정이 꺼져 있었습니다. 켜고 verify에서 검사합니다.
- 위 두 수정 후 `--export-debug "Android Debug"`로 실제 APK 생성 확인(약 60MB).
- **텍스처 mipmap 기본값**: `[importer_defaults]`로 새로 import되는 모든 텍스처에 mipmap을 생성하고, 기존 아이콘 import도 갱신했습니다(축소 표시 시 계단 현상 방지).
- **가변 폰트 굵기**: `Design.variable_font(font, weight)` 추가. `{"wght": 800}`처럼 문자열 키로 지정하면 무시되어 기본 인스턴스(대개 Thin)로 표시되는 문제를 정수 태그로 해결합니다. `assets/fonts/README.md`에 안내했습니다.
- `python3 tools/verify.py`: 51 checks, 0 failures.
