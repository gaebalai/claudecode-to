---
name: ui-style-lab
description: UI 스타일 비교용 단일 HTML 을 생성한다. 프리셋 10 종 / 색 / 폰트 / 형상을 전환하고, 컴포넌트 클릭으로 코드를 복사할 수 있다. TRIGGER when 사용자가 /ui-style-lab 또는 /ui-style-lab:ui-style-lab 를 실행하거나, 「UI 스타일 비교」 「테마 비교 도구」 「컬러 코드 비교 HTML」 이라고 요청한 때. DO NOT TRIGGER when 특정 페이지의 구현 (frontend-design), 기존 LP 개선 (unicorn-lp).
version: 1.1.0
allowed-tools: [Read, Write, Bash]
---

# UI Style Lab

`template.html` 의 플레이스홀더를 치환해 출력하기만 하는 경량 스킬.

호출명은 두 가지 — 둘 다 동작:
- `/ui-style-lab` (셸 스크립트 설치 시 standalone)
- `/ui-style-lab:ui-style-lab` (플러그인 설치 시; 플러그인명:스킬명)

## 인자

```
/ui-style-lab [타이틀] [초기테마ID]
```

두 인자 모두 생략 가능. 생략 시는 `UI Style Lab` / `midnight-mint`.

이용 가능한 테마 ID: `midnight-mint` `apple-clean` `glassmorph` `cyber-neon` `paper-brutal` `pastel-pop` `nothing-mono` `corporate-blue` `editorial` `sunset-flat`

미지의 preset 이름이 오면 `midnight-mint` 로 폴백해 조용히 계속 진행한다.

## 실행 절차

1. **template.html 경로를 다음 우선순위로 해석**:
   1. `$CLAUDE_PLUGIN_ROOT/skills/ui-style-lab/template.html` (플러그인 모드)
   2. `$HOME/.claude/skills/ui-style-lab/template.html` (셸 스크립트 설치)
   3. `$HOME/.claude/plugins/cache/*/ui-style-lab/*/skills/ui-style-lab/template.html` (캐시 fallback)

   Bash 예시:
   ```bash
   TPL=""
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/skills/ui-style-lab/template.html" ]; then
     TPL="$CLAUDE_PLUGIN_ROOT/skills/ui-style-lab/template.html"
   elif [ -f "$HOME/.claude/skills/ui-style-lab/template.html" ]; then
     TPL="$HOME/.claude/skills/ui-style-lab/template.html"
   else
     TPL=$(ls -t $HOME/.claude/plugins/cache/*/ui-style-lab/*/skills/ui-style-lab/template.html 2>/dev/null | head -1)
   fi
   ```

2. 해당 파일을 Read 하고, `{{TITLE}}` / `{{DEFAULT_PRESET}}` 을 치환한 내용을 Write 로 출력.
3. 출력 대상: 카렌트에 `output/` 이 있으면 거기, 없으면 `./`. 파일명 `ui-style-lab.html`, 충돌 시는 `ui-style-lab-YYYYMMDD-HHMM.html`.
4. OS별 open 명령:
   - macOS: `open <출력경로>`
   - Linux: `xdg-open <출력경로>`
   - Windows: PowerShell `Start-Process <출력경로>` 또는 `cmd /c start "" <출력경로>`

   실패해도 계속 진행.
5. 출력 경로를 1 행으로 보고.

## 제약

- `template.html` 은 **읽기 전용**. 개수는 스킬 갱신 (version 올림) 으로 수행.
- 덮어쓰기 충돌은 타임스탬프 부여로 회피. 사용자 확인하지 않음.
- 위 3단계 경로 모두에서 `template.html` 을 읽을 수 없는 경우는 재생성을 시도하지 않고, 설치 상태 (`~/.claude/skills/ui-style-lab/` 또는 플러그인 캐시) 의 확인을 의뢰하고 종료.
