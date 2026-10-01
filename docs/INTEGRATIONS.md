# Optional native integrations

## 현재 상태

Base는 SDK 미설치 상태에서 완전하게 실행됩니다. AdsAdapter / AnalyticsAdapter는 의도적인 no-op입니다. 테스트 광고를 실제 표시하거나 Firebase에 이벤트를 전송했다는 의미가 아닙니다. 설치된 Godot는 4.7.2이며 native plugin 조합을 빌드·검증하지 않았으므로 해당 종속성을 프로젝트에 억지로 고정하지 않습니다.

## AdMob 연결 시 추가 항목

Poing Studios의 [공식 플러그인](https://github.com/poingstudios/godot-admob-plugin)과 [설치 문서](https://poingstudios.github.io/godot-admob-plugin/)는 Godot 4.5+용 GDScript/Android/iOS 지원과 UMP를 안내합니다. 이것만으로 현재 4.7.2의 모든 기기 호환성이 검증된 것은 아닙니다. 파생 게임에서 다음을 함께 설치·고정하고 실제 Android export로 확인하세요.

1. Godot 4.7.2 Android Gradle build template (`android_source.zip` 포함 export templates).
2. 같은 릴리스의 Godot AdMob editor/GDScript addon 및 Android native plugin/AAR. 버전, checksum, native dependency lock을 파생 프로젝트에 기록합니다. 서로 다른 release의 addon/native 바이너리를 섞지 않습니다.
3. 해당 플러그인이 요구하는 Google Mobile Ads SDK와 UMP dependency. 플러그인 Gradle 설정을 사용하며 별도로 중복 추가하지 않습니다.
4. 두 Android export preset에서 Gradle 활성화, plugin 활성화, INTERNET / ACCESS_NETWORK_STATE 권한. 실제 앱 AdMob app ID 및 각 placement의 unit ID.
5. Debug에는 공식 test ID, Release에는 별도 실제 ID. [Google 공식 테스트 광고 안내](https://developers.google.com/admob/android/test-ads)의 현재 값을 사용하세요. 이 Base에는 실행 가능한 test/live ID를 기본값으로 심지 않았습니다.

## Adapter 계약

새 스크립트는 `AdsAdapter`를 상속합니다. `configure(ids)`에서 검증된 app_id, interstitial_id, rewarded_id를 받아 native SDK 설정에 그대로 사용합니다. SDK 호출은 이 adapter 내부에만 위치시킵니다.

- `request_consent()`: UMP consent info 갱신 → 필요한 form 처리 → canRequestAds 결과를 `consent_resolved`로 전달. 그 전에는 광고 요청/초기화를 시작하지 않습니다. 실패해도 앱 진행은 허용합니다. 지역별 임의 판정이나 단순 자체 체크박스로 UMP를 대체하지 않습니다.
- `privacy_options_required()` / `show_privacy_options()`: UMP privacy options 상태·화면을 연결하고 변경된 canRequestAds를 다시 emit합니다. Settings는 필요할 때만 해당 버튼을 표시합니다.
- `interstitial_ready()` / `rewarded_ready()`: 실제 캐시된 광고 객체의 준비 상태를 반환합니다. 실패 후 재로딩은 제한된 backoff를 사용합니다.
- `present_interstitial(request_id)` / `present_rewarded(request_id)`: 호출 즉시 표시를 수락했는지를 bool로 반환합니다. 실제 callback에서 `impression(id, format)`, `reward_earned(id)`, `dismissed(id)` 또는 `failed(id)`를 main thread로 전달합니다. format은 interstitial/rewarded입니다. 즉시 false를 반환하면 이후 callback을 보내지 않습니다.
- `reward_earned`는 SDK의 실제 보상 지급 callback에서만 emit합니다. close나 impression은 보상의 근거가 아닙니다. SDK가 reward/close 순서를 보장하지 않으면 adapter에서 정규화하여 reward를 먼저 전달합니다.
- `cancel(id)`은 watchdog 후 오래된 요청을 무효화하고 native surface를 안전하게 정리합니다. 늦은 callback이 다음 요청에 연결되지 않도록 request_id를 보존합니다.

앱 초기화 시 다음 API로 등록합니다. provider 인스턴스는 manager가 소유하며 다른 부모에 먼저 추가하지 않습니다.

```gdscript
AdsManager.install_adapter(provider, {
    "app_id": app_id,
    "interstitial_id": interstitial_id,
    "rewarded_id": rewarded_id,
})
```

AdsManager는 consent 전에 호출하지 않고, 실제 provider의 빈 ID를 거부합니다. Release에서 Google test publisher ID는 차단합니다. provider의 별도 test-device / force-test 설정도 debug에만 허용해야 합니다. `tools/export_release.py`는 설정 파일의 test ID를 추가로 검사합니다. SDK 내부에서 manager의 정책을 우회해 광고를 직접 표시하지 않습니다.

## Analytics / crash reporting

Firebase 등 분석 SDK가 필요한 파생 프로젝트에서 4.7.2 호환 provider와 native 설정 파일을 설치합니다. Base에는 Firebase 종속성·자격증명·Crashlytics가 없습니다. AnalyticsAdapter.record 구현은 사용자 동의/수집 활성 상태를 먼저 확인하고 이벤트를 전달해야 합니다. Base API는 개인 식별자를 생성하지 않으며 실패 시 게임을 중단하지 않습니다.

네이티브 crash 수집을 추가하더라도 원시 save나 개인정보를 로그에 남기지 마세요. 일반 GDScript에서는 존재하지 않는 SDK 클래스를 직접 참조하지 않고 별도 provider에 격리합니다. Release runtime에서 불필요한 print 로그는 남기지 않습니다.

## 실기기 통합 인수 기준

- Consent 미결정/거절/오프라인/네트워크 timeout에서도 Menu·플레이·종료 가능.
- 게임 중 interstitial/banner 없음. 종료 직후만 빈도 정책을 지켜 표시.
- Rewarded 거절/조기 닫기/실패/중복 callback/늦은 callback에 잘못된 보상 없음.
- native 광고 화면 foreground/background·Android back·오디오 복원 정상.
- Release binary와 native manifest에 test IDs/테스트 장치 설정이 활성화되지 않음.
- UMP privacy options, 분석 수집 동의 변경, 실제 전송 이벤트를 각 SDK 도구로 확인.
