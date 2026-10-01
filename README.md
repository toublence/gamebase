# Namslab Android Game Base

특정 게임을 구현하지 않은 **Godot 4.7.2 stable / GDScript** 공통 템플릿입니다. 폴더를 복사하고 게임 Scene만 연결해 사용합니다. 핵심 기능은 서버, 계정, 네트워크, 외부 SDK 없이 동작합니다. 기본 렌더러는 모바일 저사양 기기를 위한 GL Compatibility, 목표 프레임 제한은 60fps입니다.

## 시작

Godot에서 `project.godot`을 Import하고 F6 대신 F5로 실행합니다. 기본 흐름은 `Boot → Menu → Game Host → Pause / Settings → Result → Replay / Menu`입니다. 게임이 연결되지 않으면 Host의 **세션 종료** 버튼으로 결과 화면까지 확인할 수 있습니다. 점수 규칙이나 장르 로직은 없습니다. 실제 게임을 연결하면 Host 안내와 종료 버튼은 사라집니다.

## 구조

```text
scenes/             boot, menu, game, pause, result, settings
scripts/core/       앱 상태, Scene 전환, 세션, 게임 연결 계약
scripts/services/   저장, 설정
scripts/ui/         공통 디자인, Safe Area, Page, UI 서비스, components
scripts/input/      멀티터치 및 마우스 공통 PointerInput
scripts/audio/      AudioManager
scripts/haptics/    HapticManager
scripts/ads/        광고 정책과 교체 가능한 AdsAdapter
scripts/analytics/ AnalyticsService와 no-op AnalyticsAdapter
scripts/utils/      Motion tween helper
resources/          BaseConfig, Theme, AudioBusLayout
assets/             audio, fonts, icons, fx
localization/       9개 언어의 공통 문구 PO
tests/              프로덕션 export에서 제외되는 검증 Scene
tools/              검증 및 release export 진입점
```

## Autoload

등록 순서는 `SaveManager → SettingsManager → AnalyticsService → AudioManager → HapticManager → GameSession → AppManager → SceneManager → AdsManager → UI`입니다. 매니저를 게임 Scene 안에 다시 생성하지 마세요.

| Autoload | 역할 |
| --- | --- |
| SaveManager | schema, JSON, temp/backup, 손상 복구, 게임별 namespace |
| SettingsManager | 검증된 설정 변경, 즉시 저장, locale, changed 신호 |
| AnalyticsService | 6개 공통 이벤트 및 사용자 어댑터 |
| AudioManager | 지속되는 Music 플레이어, 6개 SFX voice, 3개 bus |
| HapticManager | 플랫폼 및 설정에 따른 vibration |
| GameSession | start / pause / resume / finish / restart / stop |
| AppManager | 상태, background/foreground, Android back, 종료 |
| SceneManager | 고정 route, fade, 중복 전환 잠금 |
| AdsManager | 동의, natural break, 빈도, 보상 callback, timeout |
| UI | modal stack, confirm, toast, 전환 curtain |

## 복사 후 변경할 항목

1. `project.godot`: `application/config/name`, `config/custom_user_dir_name`, `config/icon`. 저장 디렉터리는 게임마다 반드시 다르게 지정합니다.
2. `export_presets.cfg`: **두 프리셋 모두** package/name, package/unique_name, version/code, version/name. 현재 package는 `com.namslab.gamebase.template`입니다.
3. `project.godot`의 `display/window/handheld/orientation`: 6(sensor, 기본), 1(portrait), 0(landscape). 480×800은 논리 디자인 좌표이며 특정 휴대폰 해상도가 아닙니다. `canvas_items + expand`로 늘어납니다.
4. `resources/base_config.tres`의 game_scene, menu_music, game_music, ui_click.
5. `resources/base_theme.tres`와 `scripts/ui/design.gd`의 색상/간격/타이포그래피, locale의 APP_TITLE/MENU_SUBTITLE 등 브랜드 문구.

보통 Save/Settings/Scene/Audio/Haptic 매니저, 공통 modal과 입력 모듈은 수정할 필요가 없습니다. 게임 전용 Scene/스크립트는 새 폴더에 추가하세요. `.godot`, `build`, 기존 Git 이력, 자격증명은 새 게임에 복사하지 않습니다.

## 게임 Scene 연결

게임 루트 스크립트가 `GameModule`을 상속하도록 합니다. 루트는 Node이며 자식으로 게임의 Control/Node2D를 자유롭게 구성합니다. 부모 Host의 콘텐츠 Control은 Safe Area 안에 배치됩니다. 자신의 Control은 full-rect anchor를 사용하고 Node2D는 콘텐츠 크기에 맞춰 배치하세요.

```gdscript
extends GameModule

func _ready() -> void:
    session_started.connect(_start_content)
    session_paused.connect(_pause_content)
    session_resumed.connect(_resume_content)
    session_stopped.connect(_stop_content)
```

위 네 callback의 구현은 파생 게임이 담당합니다. 또는 `start_session`, `pause_session`, `resume_session`, `stop_session`을 override하고 필요 시 `super`를 호출하세요. Host는 인스턴스가 준비된 후 start를 호출합니다. 재시작은 기존 인스턴스를 해제하고 새 인스턴스를 생성합니다.

게임이 종료될 때 `complete({"title": "MY_RESULT_KEY", "value": "1,240", "best": "2,400", "message": "MY_MESSAGE_KEY"})`를 호출합니다. 숫자 포맷, 최고 기록 계산, 승패 판정은 파생 게임이 담당합니다. `best`, `value`, `message`는 생략할 수 있습니다. 공통 Base는 점수를 계산하거나 비교하지 않습니다.

일시 정지는 SceneTree 전체를 pause하고 UI/서비스만 계속 실행합니다. 게임 노드는 기본 `PROCESS_MODE_INHERIT`를 유지하세요. 앱이 background로 이동하면 pause 신호와 저장을 실행하며, foreground 복귀 후에는 사용자가 Resume해야 진행됩니다. 강제 종료 후 기본 동작은 Menu에서 새 세션 시작입니다. 이어하기 데이터가 필요하면 pause/stop 및 적절한 checkpoint에서 게임 데이터를 저장하세요. OS가 강제 종료 시 반드시 알림을 준다고 가정하지 않습니다.

## Save / Settings

```gdscript
var progress := SaveManager.get_game_data("my_game")
var saved := SaveManager.set_game_data("my_game", {"unlocked": ["a", "b"]})
SettingsManager.set_value("music", false)
SettingsManager.set_value("reduced_motion", true)
SettingsManager.set_value("language", "ko")
```

`user://save.json`에는 version(현재 2), settings, common(first_run, total_play_sessions), games가 저장됩니다. JSON으로 표현 가능한 Dictionary/Array/String/bool/유한 숫자/null만 허용합니다. namespace 조회 결과는 복사본입니다. 변경 후 반드시 set_game_data를 호출하세요. 크기 상한은 2MiB, 입력 중첩 상한은 32입니다. 큰 게임 데이터는 파생 게임의 별도 저장소로 분리하세요.

쓰기 순서는 temp 생성 → flush/close → 정상 primary를 backup으로 이동 → temp를 primary로 rename입니다. 로드는 primary → backup → temp → 기본값 순서이며 잘못된 타입/누락 필드는 기본값으로 복구합니다. v1의 sfx 설정을 v2의 sound로 마이그레이션합니다. 더 높은 schema는 **읽기 전용 기본값**으로 열어 기존 파일을 덮어쓰지 않습니다. 새 migration은 `_migrate()`에 명시적으로 추가하세요.

저장 실패는 false/신호/Toast로 전달하고 메모리의 최신 상태를 유지합니다. 디스크 부족·권한 문제에서 영속 저장 성공을 보장하지 않습니다. 설정 toggle은 즉시, volume drag는 손을 놓을 때 저장합니다. 로컬 JSON은 암호화·부정행위 방지 저장소가 아닙니다.

## Audio / Haptic

```gdscript
AudioManager.play_music(preload("res://assets/audio/my_music.ogg"))
AudioManager.play_sfx(UI.config.ui_click)
AudioManager.play_music(null) # 음악 중지
HapticManager.light()
HapticManager.medium()
HapticManager.strong()
HapticManager.success()
```

Master/Music/SFX bus와 mute/volume이 연결되어 있습니다. Music/SFX On/Off와 각 volume을 Settings에서 변경합니다. BGM은 파생 게임이 연결하며 리소스 import의 loop 옵션을 설정합니다. 기본 Base는 원본 합성 UI click만 포함합니다. null 오디오를 전달해도 안전합니다. Scene 전환에도 플레이어는 유지되고 background/광고 중에는 audio가 중지 또는 suspend됩니다.

Android VIBRATE 권한은 export preset에 포함됩니다. Android/iOS에서 Godot `Input.vibrate_handheld`를 사용하며 나머지 플랫폼에서는 no-op입니다. 실제 진동 세기·지원은 기기에 따라 다릅니다. 성공 진동은 짧은 단일 pulse이며 게임에 특정 패턴을 강제하지 않습니다.

## Pointer / UI / Motion

`PointerInput` 노드를 게임 콘텐츠 아래에 추가하고 pressed/dragged/released/cancelled를 연결합니다. `released`는 전체 변위와 누른 시간을 전달하므로 게임에서 tap/press/drag/swipe 기준을 정할 수 있습니다. 터치 index별 추적, 실제 마우스 지원, emulated mouse 중복 제거, UI에서 소비한 press 제외, pause/background에서 cancel을 제공합니다. 게임 콘텐츠의 비상호작용 Control은 mouse_filter=IGNORE로 설정하세요. UI 버튼은 일반 Godot touch→mouse emulation으로 작동합니다.

UI는 anchor/container/scroll로 구성하고 SafeArea가 화면 resize와 foreground 시 물리 inset을 논리 좌표로 변환합니다. 버튼 최소 높이는 56 디자인 단위이며 문구는 자동 줄바꿈 또는 ellipsis를 사용합니다. 긴 설정 화면은 스크롤합니다. Primary/Secondary/Icon Button, Toggle, SettingsRow, Modal, ConfirmDialog, ResultCard, LoadingIndicator를 각 파일에서 재사용할 수 있습니다. Modal은 이전 modal을 숨기고 키보드 focus 순환을 내부로 제한합니다.

`Motion.fade/pop/scale_to/slide/bounce`는 reduced_motion을 따릅니다. slide는 Container가 직접 배치하지 않는 wrapper Control에 적용하세요. Base에 상시 `_process()` 루프나 매 frame 임시 객체 생성은 없습니다. 게임의 pool/particle 수명은 파생 모듈이 관리합니다.

## Ads / Analytics

현재 기본 배포는 **광고·Analytics 네트워크 전송이 없는 no-op**입니다. 활성 게임 중 배너는 생성하지 않습니다. AdsManager의 natural-break API는 Result/FINISHED에서만 동작하며, 시작 30초 이후·완료 3회 이상·180초 간격·앱 실행당 최대 3회를 적용합니다. 같은 종료에 중복 요청하지 않습니다.

```gdscript
AdsManager.show_interstitial_on_natural_break()
# 사용자가 선택한 버튼에서, 먼저 pause한 뒤 호출:
AdsManager.show_rewarded(func(earned: bool):
    if earned:
        grant_game_reward())
```

미설치/미동의/미준비/실패/90초 timeout이면 진행을 차단하지 않고 보상 callback(false)을 반환합니다. SDK의 reward_earned와 dismissed가 모두 확인된 요청에만 callback(true)을 1회 전달합니다. no-op은 가짜 보상이나 impression을 만들지 않습니다.

네이티브 연결 절차와 계약은 [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md)를 따릅니다. 이 환경에는 AdMob/Firebase 플러그인이 없으며 Godot 4.7.2 Android 네이티브 조합의 빌드·기기 호환성을 검증하지 않았습니다. 광고가 이미 연결되었다고 간주하지 마세요.

AnalyticsAdapter의 `record(event, parameters)`를 override하고 `AnalyticsService.set_adapter()`로 주입합니다. 공통 이벤트는 game_start, game_end, game_restart, settings_changed, ad_impression, rewarded_completed입니다. 기본 어댑터는 저장·로그·업로드를 하지 않습니다. 개인정보·게임 전용 이벤트를 Base에 넣지 않으며 consent가 필요한 provider는 provider가 전송을 gate해야 합니다.

## Localization

English, Korean, German, Spanish, French, Japanese, Arabic, Simplified Chinese, Traditional Chinese의 공통 메뉴 문구가 `localization/*.po`에 있습니다. UI에는 번역 key를 사용합니다. 새 key는 모든 PO에 추가하고 새 언어는 `project.godot` translations 및 SettingsManager.LOCALES, Settings의 언어 표시 목록에도 등록하세요. 변경은 런타임에 반영됩니다. fallback은 English, 기본 선택은 device language입니다.

RTL은 Godot locale layout direction을 상속하고 방향을 고정하지 않습니다. 시스템 글꼴 및 fallback을 사용하므로 추가 다운로드 없이 실행됩니다. 정확한 브랜드 서체/모든 기기에서 동일한 glyph를 원하면 사용권을 확인한 글꼴을 assets/fonts에 넣고 Theme의 font를 교체하세요. 번역의 자연스러움·Arabic shaping·CJK fallback은 출시 전에 실기기로 확인하세요.

## Android

Android Debug: 표준 APK template, arm64 + armeabi-v7a, immersive/edge-to-edge, VIBRATE만 활성화. min/target SDK는 템플릿 자체 값(24/36)을 쓰며 프리셋에서 덮어쓰지 않습니다(Gradle 빌드 없이 SDK를 지정하면 Godot가 내보내기를 거부). Release 프리셋만 min SDK **24**, target SDK **36**을 명시합니다. 인터넷 권한은 꺼져 있습니다. 기존 설치된 4.7.2 debug template의 manifest도 min 24 / target 36입니다. Android Release: Gradle AAB, 같은 ABI/SDK, 별도 release signing.

현재 머신에는 Godot 4.7.2, Android debug/release APK templates, JDK 17, Android SDK 36/build-tools 36이 있습니다. Debug APK는 Editor Export 또는 `godot --headless --path . --export-debug "Android Debug" build/<name>-debug.apk`로 생성됩니다(2026-10-01 실제 생성 확인).

Release AAB에는 Godot **4.7.2의 Android build template(source/Gradle)**가 추가로 필요합니다. 현재 export_templates 폴더에는 android_source.zip이 없습니다. 정확히 일치하는 전체 export templates를 설치하고 Project → Install Android Build Template을 실행하세요. JDK/SDK 경로는 Editor Settings → Export → Android에서 설정하며 머신 경로·keystore·비밀번호는 저장소에 커밋하지 않습니다. release signing은 Export 창의 보안 자격증명으로 설정하세요.

이름/package/user-dir 변경 후 `python3 tools/export_release.py`를 사용하면 placeholder와 설정 파일의 Google test publisher ID를 검사한 뒤 release export를 실행합니다. Editor 직접 export 시에도 AdsManager는 release에서 Google test publisher ID를 가진 실제 adapter를 활성화하지 않습니다. 실제 SDK 자체의 테스트 모드도 provider에서 `OS.is_debug_build()`에만 연결하세요.

## Debug / Release / 검증

기본 화면은 템플릿 자체의 실행 가능한 shell입니다. 테스트 전용 게임이나 진단 버튼은 release UI에 포함하지 않습니다. `tests`, `tools`, `docs`, Markdown 문서는 **Debug/Release 모두 export에서 제외**되며 production에서 tests를 preload하지 않습니다. 별도 검증 Scene은 debug engine + 명시적 `--verify-base` 인자에서만 실행되고 별도의 `user://verification/` 저장 경로를 사용합니다.

```sh
python3 tools/verify.py
# 다른 환경:
GODOT=/path/to/godot python3 tools/verify.py
```

검증 명령 하나가 리소스 경로/언어 key/export 설정 검사, headless editor import/parse, 실제 Scene 전환·저장 복구·설정 영속성·lifecycle·Audio bus·광고 fallback·RTL 검증을 실행합니다. APK/장시간 빌드나 SDK 설치는 하지 않습니다. 각 Godot 프로세스의 시간 제한은 50초입니다. 실제 실행 결과는 [docs/VALIDATION.md](docs/VALIDATION.md)에 기록합니다.

실기기 추가 확인: notch/navigation bar·회전·접기/분할 화면, 작은 폰/tablet, 멀티터치 취소·Android back, background 복귀/강제 종료 후 저장, 소리·진동, CJK/Arabic glyph, 60fps/메모리, release 서명·AAB, native provider 연결 시 UMP/광고/분석. Headless 검증은 렌더링 품질이나 기기 성능을 보장하지 않습니다.
