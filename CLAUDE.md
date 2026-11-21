# Pit Wall — 작업 규칙 (AI 협업용)

> 다른 AI 도구용 같은 내용: `AGENTS.md` (규칙을 바꾸면 두 파일을 같이 고칠 것). 할 일·결정 사항: `docs/작업목록.md` (사용자용 요약 `docs/업데이트예정.md` — 항목이 끝나거나 추가되면 같이 고치고 Claude 프로젝트 사본 claude/pitwall-업데이트예정.md 도 갱신). 새 대화·다른 AI 지시문: `docs/AI_공통지시문.md`.

## 프로젝트
- F1·WEC 피트월 전략 시뮬레이션. Godot 4.7, GDScript, 기준 해상도 1280×720(가로), 화면 비율에 따라 가로(PC·가로 폰)/세로(세로 폰) 배치를 자동 전환.
- 원본은 단일 HTML 버전(v16.1). 시뮬레이션 계산식은 원본을 그대로 옮긴다 — 밸런스는 원본에서 수백 판 몬테카를로로 검증한 결과다. 수치를 바꾸면 이유를 커밋 메시지에 남긴다.
- 사용자는 개발 초보다. 기술적 판단은 AI가 내리고, 사용자에게는 실행·확인 방법을 쉬운 말로 안내한다.

## 게임 설계 방향 (사용자 2026-11-16)
- 목표: 마니악한 "시뮬레이터 느낌" — 실제 규정·실제 현상에 근거한 깊이. 단, 파고들수록 피곤해지면 안 된다.
- 판단 기준 (새 기능·수치 변경마다 확인):
  1. 현실 근거: 실제 레이스에 있는 현상·규정인가 (출처 확인, 연도별 규정은 데이터로)
  2. 공짜 선택 없음: 모든 선택지에 분명한 장점과 대가. 늘 정답인 값이 생기면 실패
  3. 상황마다 정답이 다름: 서킷·날씨·타이어·순위에 따라 최적이 움직여야 판단할 이유가 생긴다
  4. 숫자로 보이게: 고르는 순간 예상 효과(랩당 ±초, 마모 ±%, 다음 피트 랩 등)를 보여준다. 감으로 찍게 두지 않는다
  5. 찾아가는 재미: 숨은 최적값 + 연습 피드백(드라이버 말·엔지니어 추천 범위)으로 찾는다. 처음부터 정답 공개 안 함
  6. 깊이는 선택: 기본값·엔지니어 추천·자동이 항상 합리적이라 안 건드려도 손해가 크지 않다. 파고드는 사람만 이득
  7. 반복 노동 금지: 같은 판단을 매 랩·매 스틴트 반복시키지 않는다 (계획표·자동 처리 + 중요한 순간만 직접)
  8. 조작은 적게, 정보는 충분히: 4바퀴 따로 조절 같은 과한 조작 대신 슬라이더 하나 + 좋은 정보
  9. AI 도 같은 규칙: 플레이어만의 시스템 금지, AI 는 팀 능력만큼 오차
- 결과 확인: 복기·무전으로 "그 선택 때문에 얼마 얻고 잃었나"를 알려준다

## 코드 작성 원칙 (ponytail 방식, 2026-11-18 도입)
- 가장 작은 "완전한" 수정: 요청을 다 해내는 가장 적은 코드. 이미 있는 함수·패턴 재사용 → Godot 기본 기능 → 새 코드 순. 요청 안 한 옵션·추상화·"나중을 위한" 코드 금지 (단, 사용자가 정한 게임 깊이·기능은 줄이지 않는다)
- 고치기 전에 그 함수를 부르는 곳을 전부 찾고(grep), 원인을 공통 코드에서 한 번에 고친다
- 새 분기·계산 로직은 tests/ 에 확인 한 줄이라도 남긴다
- 한계를 알고 쓴 임시 처리는 주석으로: `# shortcut: <한계>, <언제 바꿀지>` — 나중에 grep 으로 모아 본다
- 작업 끝에 한두 줄: 확인 못 한 것·남은 위험
- 사용자 설명은 지금처럼 쉬운 말로 (코드는 짧게, 설명은 친절하게)

## 구조 원칙
- `scripts/sim/` 은 화면을 몰라야 한다(Node·UI 참조 금지). RefCounted 기반, 헤드리스로 돌아가야 한다.
- `scripts/ui/` 는 sim 상태를 읽어 그리기만 한다. 규칙 로직을 UI에 넣지 않는다.
- 데이터는 `data/*.json`. 코드에 팀·서킷 숫자를 하드코딩하지 않는다.
- 스크립트 간 참조는 `class_name` 대신 `const X = preload("res://...")` 를 쓴다(헤드리스 `--script` 실행에서도 동작하도록).

## GDScript 주의
- 타입이 정해지지 않은 값(딕셔너리 조회, 타입 없는 객체 속성)에 `:=` 를 쓰면 컴파일 에러가 난다. 지역 변수는 `var x = ...` 또는 `var x: float = ...`.
- 한 줄에 문장 하나. 들여쓰기는 탭.
- UI는 코드로 생성한다(.tscn은 최소한으로).

## 검증
- APK 는 사용자가 요청할 때만 만든다 (.github/workflows/apk.yml 은 수동 실행 전용).
- 푸시하면 GitHub Actions(.github/workflows/ci.yml)가 Godot 4.7.2로 문법 검사 · sim/주말/커리어/UI 테스트 · 밸런스 점검 · 화면 캡처를 돌린다. 캡처는 `ci-shots` 브랜치에 jpg로 올라간다 (`git fetch origin ci-shots` 후 확인).
- 로컬: `godot --headless --path . --script res://tests/sim_smoke.gd` 등.
- 밸런스 변경 시 여러 서킷·여러 시드로 스톱 분포·팀별 순위를 비교한다.

## 남은 단계
1. F1 퀵 레이스 이식 (완료)
2. 연출 업그레이드 (완료)
3. 예선 · HQ · 경제 · 커리어 이식 (완료, F1만. WEC 커리어는 6단계)
4. 스폰서 개편 (완료: scripts/sim/career.gd 스폰서 절)
5. 하위 리그 (완료): F2 스프린트+피처, F3 피트 없음·성장 ×2, WEC LMGT3(브론즈 25%)·LMP2(실버 20%)
6. WEC 모드 (완료): race_sim.gd 의 is_wec() 분기, data/wec.json · circuits_wec.json
7. 편의·콘텐츠 (완료): 난이도 4단계(race_sim DIFF_PACE/DIFF_STRAT, 보통 = 원작), 레이스 지시·전략 A/B·자동 피트(make_plans/_my_auto_decision), 인터·웻 박스 버튼, WEC FA 시장·라인업, F2/F3 로스터 능력치(이름 해시), 시즌 결산 화면(season_view.gd·트로피), 저장 슬롯 3개(1번 = 예전 파일), "?" 도움말(help.gd·help_text.gd), 비·SC·우승 연출
8. 레이스 화면·전략 깊이 (완료): race_panel.gd(칩·탭·엔지니어 제안·팀 오더), 세부 셋업(race_sim setup_extra — 표준이면 0), 그리드 플랜 직접 설계(eval_plan/set_custom_plans), 복기(debrief.gd), 라이벌 카드(rival_card.gd), 페널티(add_penalty), 커리어 이벤트(career _maybe_event/resolve_event, next_mods), 설정(settings.gd)
9. 셋업 찾기·AI 전술 (완료): 셋업 슬라이더(setup_opt 숨은 최적값, weekend bands 엔지니어 추천 범위, 연습 16랩), AI 주행 전술(_ai_tactics), AI 언더컷·오버컷·트래픽 회피·두 대 전략 분리·팀 오더·SC 스테이아웃, 크루 실수(_crew_error). 횟수는 sim.tally 로 확인
10. 이어하기·기록·WEC 규정 (완료): 레이스 중간 저장(race_save.gd, 선두 랩마다·앱 내릴 때·⏏ 버튼), 기록실(records.gd·records_view.gd), WEC 2026 타이어 규정(wecComps·세트 제한·워머 금지·하이퍼폴 미디엄)과 주행 시간 규정(wecHours, drive_limits/must_swap), 드라이버 피로·트래픽 접촉, AI 예보·SC 찬스·마지막 스틴트 타이어 계산, 성능 표시 설정
- 참고: 보통 난이도에서 단순 봇이 AI보다 레이스당 약 2계단(예선 포함 3.5계단) 앞선다 (tests/calib.gd 난이도별 출력으로 비교).
11. 커리어 깊이 (완료): 설비 Lv.1~10(fac_lv/fac_x, 리그 상한 fac_cap), 아시안 르망 성장 보정(cal_len 비례), F1 승격 시 기본 차 = 그리드 최하위 수준(_on_tier_change), HQ 순위표·라운드별 일정 칸(_standings_grid/_schedule_card, hq round_res), F1 부품 재고(pu_state pool/cur/prac, pu_add·pu_mount·pu_set_practice, 강등 합산, AI는 _ai_pu_after_race → ai_grid_pen), 파트별 인력(STAFF_DEPTS 5파트, staff_refresh_pool 시즌마다, 특성·AI 스카우트 _ai_staff_scout)
12. 버그 수정 주간 (완료): 저장 후 나가기 → 메인(본부는 레이스 끝날 때까지 못 감), 본부 지역 팀별 고정(data team_region)·연구 철학/규정 주기 시즌 전 잠금(set_branch/set_dev_target), 피트 예약·막판 무전 정리, F2·F3 ERS 없음(rules.no_ers, has_ers), F2·F3 예선 30분 단일(rules.fmt, weekend single_quali)·리그별 할당(ALLOC_F2/F3, rules.dry, AI 도 _ai_sets)·새/쓴 세트 선택(take_set_mode), 리그별 FA 시장(data/names.json gen_person), WEC 교대 드라이버 직접 선택(drv_block, wec_req.drv)
13. 주말 깊이 D①② (완료 2026-11-21): 타이어 공기압 psi(race_sim press_rise/psi_rec/press_u/press_fx, 서킷 psiMin·trackT, weekend psi_band, 예선 끝 결승용 자동 조정), 세부 셋업 = 타협(SETUP_CH 두 갈래 득실 × setup_w 서킷 비중, setup_opt(c, race) 예선/결승 최적, SETUP_WEAR, setup_pref 드라이버 취향 = 실수만, 서스펜션↔공기압 PSI_SUSP, weekend 엔지니어 등급 eng_grade·틀린 추천·setup_view 득실 숫자)
