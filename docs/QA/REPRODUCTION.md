# Outtap 감사 재현 절차

모든 조작은 실제 게임 UI로 수행한다. 원본 저장을 초기화하지 않는다. 이 문서의 체크포인트는 감사에서 플레이한 결과이며 정답/치트가 아니다.

## 큰 판 시작 화면과 전체 보기

1. 별도 신규 저장 환경에서 현재 메인 Scene을 실행한다.
2. 이야기 카드와 정상 UI를 거쳐 1→2→3을 순차 진행한다.
3. 3 최초 판의 좌우 경로가 화면 밖으로 이어지는지 관찰한다.
4. 오른쪽 아래 전체 보기 버튼을 누른다. 모두 보이는 대신 머리가 작아지는지 비교한다.
5. 4와 5에서도 같은 절차로 확인한다. 5의 현재 로그상 board는 29×36, arrows는 93이다.
6. 빈 공간 더블탭으로 확대하고 빈 공간 드래그로 이동한다. 실제 Android 핀치는 별도 검증한다.

증거: screenshots/005_level03.png, 006_level03_fit.png, 008_level04_fit.png, 010_level05_hard_start.png.

## 연습 충돌과 실수 표시

1. 3에서 화면상 앞이 막힌 화살표를 선택한다.
2. 막혔다는 안내를 관찰한다. 연습에서는 하트가 없다.
3. 정상 조작으로 완료한다.
4. 이번 세션은 collisions=2지만 clear card mistakes=0, perfect=true였다. 이는 연습 정책으로 보이며 오류로 확정하지 않는다.

증거: screenshots/007_level03_clear.png 및 logs/analytics_events.json.

## 실패 후 홈 문구와 복귀

1. 정상 플레이 중 하트 3개를 잃어 실패 카드를 연다. 일부러 진행 저장을 바꾸지 않는다.
2. 홈을 누른다. 이번 세션은 스테이지 5 / 진행 중 / 계속하기로 표시됐다.
3. 계속하기를 누르면 하트 0 실패 카드가 복원된다.
4. 실패 상태를 명시한 재도전 문구와 비교 평가한다.

증거: screenshots/011_level05_failure.png, 012_home.png. 실제 실패 직후 저장은 session_checkpoint/save.json / save.json.bak에 보존했다. 원본 사용자 저장 위에 복사하지 않는다.

## 음악·효과음·음성 토글

1. 홈 오른쪽 위 설정을 연다.
2. 음악만 끄고 효과음은 켠 상태를 유지한다.
3. 음성 칭찬 토글도 독립적으로 끈다.
4. 이번 세션은 시각 토글 상태만 검증했다. 출력 정지·볼륨·왜곡·믹싱은 청취 장비로 재검증한다.

증거: screenshots/013_music_off_sfx_on.png.

## 자동화 실패와 재시작 오염

1. 하트가 적은 상태에서 여러 좌표 클릭을 연속 발행하면 중간에 실패 카드가 열릴 수 있다.
2. 남은 클릭이 실패 카드의 다시 시작(무료) 버튼 위치와 겹치면 새 시도가 시작된다.
3. 이번 로그는 level_failed→level_restarted→level_started(retry_count=1)를 기록했다.
4. 정상 인간 조작 재현은 확인하지 않았다. 이 자동화 방식의 결과를 사람의 실패율로 해석하지 않는다.
5. 이후 QA는 입력 하나 또는 상태가 유지된다는 확신이 있는 작은 묶음 뒤 화면을 관찰한다.

## 광고 지원 불가 상태

1. Mac에서 설정을 내려 광고 진단을 연다.
2. provider unsupported, SDK not_started, UMP 미진행을 확인한다.
3. 실패 후 광고 opportunity가 UNSUPPORTED_PLATFORM으로 생략되고 실패 UI/홈 복귀가 가능한지 확인한다.
4. 실제 AdMob 표시·보상·광고 종료 복귀는 Android에서 별도 수행한다.

증거: screenshots/014_ads_unsupported.png, logs/godot_runtime.log.
