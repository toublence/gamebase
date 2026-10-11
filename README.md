# Outtap (아웃탭)

얽힌 화살표를 하나씩 빼내는 Android 퍼즐 게임입니다. Godot 4.7.2 stable(GL Compatibility)과 GDScript로 만들었고, 패키지 이름은 `com.namslab.outtap`입니다.

규칙(`arrow-path-2`)은 다음과 같습니다.

- 화살표는 여러 칸에 걸친 긴 경로입니다. 머리는 마지막 칸이 향하는 방향을 가리킵니다.
- 머리 앞이 판 끝까지 비어 있으면, 화살표가 자기 경로를 따라 미끄러지며 밖으로 빠져나갑니다.
- 막힌 화살표를 누르면 하트가 하나 줄어듭니다(연습 판은 줄지 않음). 다시 시작은 언제나 무료입니다.

## 실행

- **편집기:** Godot 4.7.2에서 `project.godot`을 열고 F5로 실행합니다.
- **테스트 전체 실행:** `python3 tools/run_tests.py`. 1만 판 생성기 검사를 빼려면 `--quick`을 붙입니다.
- **기본 정적 검사:** `python3 tools/verify.py`.
- **디버그 APK:** `godot --headless --path . --export-debug "Android Debug" build/outtap-debug.apk`. Gradle 빌드와 광고 플러그인(`addons/outtap_ads`)을 사용합니다.

## 구성

```text
game/arrows/        규칙(ArrowBoard), 레벨 형식, 풀이기, 생성기, 실루엣, 세션, 보드 화면
game/services/      레벨 저장소, 진행 저장(Progress), 리그 규칙, 소리·음성·진동(Feel)
game/ui/            HUD 위젯, 클리어 카드, 리그 창, 꾸미기 창, HARD 배너, 핀치 안내
game/view/          배경 장면(Scenery, Backdrop), UI 색, 효과 파티클
game/data/v2/       캠페인 20스테이지(campaign.json, 빌드 산출물)
scenes/             boot, menu, levels, game, pause, settings, result
scripts/            게임베이스 공통(저장, 설정, 오디오, 광고, 분석, UI)
assets/audio        효과음·배경음(직접 합성)
assets/voice        음성 칭찬 14개(AI 합성, assets/voice/README.md)
tools/              레벨 빌더·검증기·미리보기, 오디오 합성·분석, 음성 생성, 테스트 실행기
tests/              자동 테스트(내보내기에서 제외)
docs/               설계·검증·오디오·광고·QA 문서
```

## 레벨 파이프라인

1~4스테이지는 손으로 설계했습니다. 5스테이지(첫 HARD)는 직접 편집할 수 있게 별도 파일로 두었습니다. 6~20스테이지는 생성 후보 중에서 골라 고정했습니다.

- `tools/levels_src/chapter1_hand.txt`: 1~4스테이지
- `tools/levels_src/a005_hard.txt`: 5스테이지
- `tools/levels_src/chapter1_gen.txt`: 6~20스테이지
- `tools/levels_src/chapter1_specs.json`: 생성 기준

```bash
godot --headless --path . -s res://tools/build_arrow_levels.gd -- build
```

빌드할 때마다 모든 판을 실제 규칙으로 다시 검증합니다. 검사 항목은 구조, 풀이 가능 여부, 저장된 풀이 재생, 실루엣 중복 금지입니다. `python3 tools/validate_arrow_levels.py`는 게임 코드를 쓰지 않는 독립 재구현으로 다시 확인합니다. 자세한 내용은 [docs/LEVEL_VALIDATION.md](docs/LEVEL_VALIDATION.md)에 있습니다.

## 문서

- [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md): 게임 설계. 난이도 곡선, HARD, 황금 화살표, 개인 리그, 장면, 터치·확대
- [docs/LEVEL_VALIDATION.md](docs/LEVEL_VALIDATION.md): 생성기, 지표, 선정 기준, 검증
- [docs/AUDIO.md](docs/AUDIO.md): 효과음·배경음·버스 믹싱·음성, 객관 분석 결과
- [docs/ADMOB_INTEGRATION.md](docs/ADMOB_INTEGRATION.md): 광고 연동과 노출 규칙
- [docs/QA_REPORT.md](docs/QA_REPORT.md): 실행한 테스트와 결과, 확인하지 못한 항목
- [history.md](history.md): 변경 이력
- [docs/BASE_TEMPLATE.md](docs/BASE_TEMPLATE.md): 원래 게임베이스 안내(참고용)
