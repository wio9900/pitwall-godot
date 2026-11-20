# AI 공통 지시문

> 사용자가 새 대화·다른 AI 에게 맨 위에 붙여 쓰는 글. 규칙이 바뀌면 이 파일도 같이 고친다.

---

## A. 새 대화 시작용 (Claude, GitHub 연결된 대화)

```
Pit Wall 작업 이어서 하자.
- 저장소: wio9900/pitwall-godot, 브랜치 feat/career-depth (main 합치기는 내가 직접 함)
- 먼저 CLAUDE.md(작업 규칙)와 docs/작업목록.md(할 일·결정·완료)를 읽고 시작해
- 내가 "수정"이라고 하기 전에는 새 요청을 작업목록 "수정 대기"에 원인·방향과 같이 올리기만 해
- 다른 AI 가 준 코드를 붙여넣으면: 바뀐 부분만 최신 코드에 맞춰 넣고(파일 통째 교체 금지) 테스트·CI 후 푸시
- APK 는 내가 달라고 할 때만
- 지금 할 일: (여기에 적기. 예: 수정 10, 9)
```

---

## B. 다른 AI 에게 일 시킬 때 (GitHub 접근 가능, 2026-11-21~)

```
너는 Godot 4.7 GDScript 게임 "Pit Wall"(F1·WEC 피트월 전략 시뮬레이션)의 게임 프로그래머야.
저장소: wio9900/pitwall-godot
- feat/career-depth 브랜치에서 새 브랜치 ai/<작업이름> 을 만들어 작업해. feat/career-depth·main 에 직접 푸시하지 마.
- 먼저 AGENTS.md(규칙)를 읽고, docs/작업목록.md 에서 아래 할 일의 배경을 확인해.
- 필요한 파일만 읽어 (race_sim.gd·race_view.gd 는 크니 필요한 함수만).

## 할 일
(여기에 D절 프롬프트 하나를 붙이기)

## 꼭 지킬 것
- scripts/sim/ 은 화면을 모른다 (Node·UI 참조 금지). UI 는 sim 을 읽어 그리기만.
- 팀·서킷 숫자는 data/*.json 에. 코드에 하드코딩 금지.
- 타입 없는 값(딕셔너리 조회 등)에 := 금지 → var x = ... 또는 var x: float = ...
- 들여쓰기 탭, 한 줄에 문장 하나, 주석·화면 글은 쉬운 한국어.
- class_name 대신 const X = preload("res://...")
- 시뮬레이션 계산식·밸런스 숫자는 바꾸지 마. 바꿔야 할 것 같으면 PR 설명에 이유와 함께 보고만.
- 요청 안 한 기능·옵션 추가 금지. 가장 작은 완전한 수정. 새 분기·계산은 tests/ 에 확인 한 줄.
- docs/작업목록.md · docs/업데이트예정.md 는 고치지 마 (Claude 가 합치면서 정리).
- APK 빌드·서명 키는 건드리지 마.

## 끝나면
- ai/<작업이름> 을 푸시하면 GitHub Actions(ci.yml)가 자동으로 테스트·화면 캡처를 돌린다. 통과 확인.
- feat/career-depth 로 PR 을 열고, 설명에: ① 바꾼 함수 목록 ② 직접 확인 못 한 것 ③ 발견했지만 손대지 않은 문제
```

사용자: 다른 AI 가 PR 을 열면 Claude 대화에서 "PR #번호 합쳐줘"라고 하면 된다 (Claude 가 검토 → 합치기 → 작업목록 정리).

---

## C. 일 나누기 기준

| 다른 AI 가 코드 작성 → Claude 는 합치기·테스트·CI 만 | 다른 AI 가 코드 작성 → Claude 가 검토 후 합치기 | Claude 가 직접 |
|---|---|---|
| 작은 것: 화면 표시·문구·버튼·데이터 수정 (2~4개 묶어서 한 번에 넘기기) | 중간: 파일 1~3개짜리 작은 기능, 화면 쪽 개편, 재현 테스트로 좁힐 수 있는 버그 | 무거운 것: 시뮬 계산식·밸런스(calib)·AI 규칙·저장 파일 형식 변환, 원인 모를 버그 추적, 여러 파일이 얽힌 설계 |

- 이유: 무거운 것은 테스트를 통과해도 밸런스가 조용히 틀어지거나 예전 저장이 깨질 수 있어 검토로 잡기 어렵다.
- 한 줄짜리 수정은 넘기지 말고 Claude 에게 바로 (넘기고 합치는 비용이 더 큼).
- 작업목록은 Claude 만 고친다 (다른 AI 결과를 합칠 때 상태를 완료로 옮김).

사용량 아끼기: 묶음 하나 끝나면 새 대화(A 붙이기) · 여러 개를 한 번에("수정 9, 10") · 간단한 합치기·APK 는 가벼운 모델로.

---

## D. 다른 AI 작업 프롬프트 (B절 지시문 뒤 "할 일" 자리에 그대로 붙이기)

### D-1. 연료 패널 묶음 — 첨부: AGENTS.md, scripts/ui/race_panel.gd, scripts/sim/race_sim.gd(읽기만), scripts/ui/kit.gd(읽기만)

```
## 할 일: WEC 레이스 피트 탭의 급유 슬라이더 개선 (화면만, sim 계산은 건드리지 마)

배경: race_panel.gd 의 WEC 피트 탭에 급유 슬라이더가 있다.
- 만드는 곳: _build_pit() 안 "_w_fuel_sl = HSlider.new()" 부분. 값은 탱크 대비 0.0~1.0 (step 0.01).
- 갱신하는 곳: _refresh_pit(c) 안 "if wec:" 블록. 지금 _w_fuel_txt 에
  "급유 후 N랩 주행 → 다음 피트 약 L.. (가득이면 L..) · 체커까지 약 N랩" 과 가득 대비 손익을 쓴다.
- 슬라이더를 움직이면 _on_w_fuel_sl(v) 가 draft[sel]["fill"] 을 바꾸고 refresh() 한다.
- 쓸 수 있는 값 (전부 이미 있음, 새로 계산식 만들지 마):
  RS.TANK = 탱크 크기(연료 단위), c.fuel = 지금 연료,
  sim._wec_burn(c, "std" / "lean" / "rich") = 그 모드의 랩당 연료 소모 (lean=세이브, rich=리치),
  sim.laps_to_go(c) = 체커까지 남은 랩, sim.next_stop(c) = 다음 계획 정차 (null 이거나 {"lap": 정수, "comp": ...}),
  c.lap = 지금 랩.

할 일 1 — 슬라이더 양옆에 −/+ 버튼
- 슬라이더를 HBoxContainer 하나에 넣고 왼쪽에 "−", 오른쪽에 "+" 버튼 (K.btn 사용, 글자 18, 최소 크기 48×40 — 폰에서 누르기 쉽게).
- 한 번 누를 때 표준 모드 기준 0.5랩만큼: 0.5 * sim._wec_burn(c, "std") / RS.TANK.
- 범위: 최소 = 지금 연료(c.fuel / RS.TANK), 최대 = 1.0. 범위 밖으로 안 나가게 clampf.
- 누른 뒤 처리는 이미 있는 _on_w_fuel_sl(새 값) 을 불러서 같게 (새 저장 로직 만들지 마).
- "급유 안 함" 상태(_w_fuel_sl.editable == false)일 땐 두 버튼도 disabled.
- 새 버튼 변수 2개는 _w_fuel_sl 변수 선언 바로 아래에.

할 일 2 — 모드별 주행 가능 랩 한 줄
- _w_fuel_txt 맨 아래에 한 줄 추가:
  "이 양이면  표준 N랩 · 세이브 N랩 · 리치 N랩" (소수 한 자리)
  N = maxf(c.fuel, RS.TANK * fill) / sim._wec_burn(c, 모드).
- 지금 고른 연료 모드(c.fuel_mode)는 굵게([b]).
- 색은 기존처럼 설명 회색 #8b98a5, 숫자만 흰색.

할 일 3 — 모자라면 경고
- 목표 랩 = sim.next_stop(c) 가 있으면 그 "lap" - c.lap, 없으면 sim.laps_to_go(c).
- 지금 연료 모드 기준 주행 가능 랩(할 일 2의 c.fuel_mode 값)이 목표 랩보다 작으면
  빨간(#ef4444) 한 줄: "⚠ 다음 계획 정차(L52)까지 1.3랩 모자라요 → 더 넣거나 세이브" (계획이 없으면 "체커까지").
- 모자라지 않으면 아무것도 안 씀.

꼭: 함수 _build_pit, _refresh_pit 는 바뀐 부분이 있으면 함수 전체를 돌려줘. _on_w_fuel_sl 은 바꾸지 마.
새 함수가 필요하면(예: _on_w_fuel_step(dir: int)) "_on_w_fuel_sl 바로 다음"에 넣는다고 적어줘.
확인: F1 레이스(wec 아님)에선 이 화면이 안 보이니 영향 없어야 함.
```

### D-2. 트랙 위 차 그림 마무리 (수정 18b ②③) — 브랜치 ai/car-labels, 볼 파일: scripts/ui/race_view.gd, scripts/ui/kit.gd(읽기만), data/car_art.json(읽기만)

```
## 할 일: 트랙 위 팀 그림 차에 타이어 색 점 + 확대했을 때만 이름표 (화면만, sim 은 건드리지 마)

배경: race_view.gd 는 팀 그림이 있으면 _draw_car_tex(c, tex) 로 PNG 를 그리고, 없으면 코드 그림(_draw_car)을 그린다.
코드 그림 F1 은 바퀴마다 컴파운드 색 띠가 있는데(_draw_car 안 tcol = Color(sim.TYRE_HEX[c.comp])), 그림 차에는 없다.
_draw_car_tex 는 이미 draw_set_transform(pos, ang, sc) 안에서 불린다 → 차 기준 좌표(앞 = +x, 차 길이 L, 폭 W)로 그리면 된다.

할 일 1 — 그림 차 뒷바퀴 자리에 컴파운드 색 점
- _draw_car_tex 안, 그림을 그린 뒤 · DRS 표시 앞에: 뒷바퀴 두 곳(대략 x = -L*0.33, y = ±W*0.42)에
  반지름 L*0.035 정도의 원을 Color(sim.TYRE_HEX[c.comp]) 로. 테두리 없이, 그림을 많이 가리지 않게.
- F1(오픈 휠)과 HY(풀 카울) 위치가 다를 수 있으니 c.cls 로 x·y 비율만 다르게 (숫자는 함수 위 const 딕셔너리 하나로).
- 밤(sim.night)에도 보이게 약간 밝게 해도 됨.

할 일 2 — 확대 추적 때만 다른 차 이름표
- 차가 화면에서 충분히 클 때만(_car_scale(false) >= 2.6 정도, const 로) 내 차가 아닌 차 위에 c.code 를 작게(11~12px) 표시.
- 위치·글자 그리기는 _draw_my_labels 의 방식(draw_string_outline + draw_string)을 따라 하되, 색은 kit.gd 의 DIM, 내 차는 이미 이름표가 있으니 제외.
- 화면 밖 차는 건너뛰기 (Rect2(Vector2.ZERO, size).grow(40) 안에 있는지 확인) — 22대 + WEC 60대에서도 가볍게.
- 새 함수 _draw_other_labels(font) 로 만들고 _draw() 에서 _draw_my_labels(font) 바로 앞에서 부르기.

## 확인
- 전체 화면(확대 안 함)에서는 이름표가 안 보여야 함. 추적(#1 추적)으로 확대하면 주변 차에만 보여야 함.
- 그림 없는 팀(Williams 등, 코드 그림)은 지금처럼 그대로.
```
