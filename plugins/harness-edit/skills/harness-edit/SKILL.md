---
name: harness-edit
description: ".claude 하네스 설정을 시각화 HTML 로 직관적으로 편집하고, JSON 차분을 실제 파일에 반영한다. TRIGGER when 사용자가 /harness-edit 또는 /harness-edit:harness-edit 를 실행하거나, '하네스 편집', '설정을 직관적으로 바꾸고 싶다'고 요청한 때. DO NOT TRIGGER when 단발의 자명한 설정 변경 (직접 편집 / update-config 로 충분)."
version: 2.0.0
allowed-tools: [Read, Edit, Write, Bash, Glob, Grep]
---

# /harness-edit

스킬에 동봉된 `references/visualizer.html` 을 편집 모드로 열고, 사용자가 GUI 로 만든 차분 JSON 을 해석해 `~/.claude/settings.json` 등에 반영한다.

호출명은 두 가지 — 둘 다 동작:
- `/harness-edit` (셸 스크립트 설치 시 standalone)
- `/harness-edit:harness-edit` (플러그인 설치 시; 플러그인명:스킬명)

## 흐름

```
① /harness-edit                      → HTML 을 open
② 사용자가 GUI 에서 편집 → 「Claude 에 적용」 버튼으로 JSON 복사
③ /harness-edit <diff-json>          → 미리보기 → 확인 → 적용
```

## 인자

- 인자 없음 / `--open`: HTML 을 열기만 함
- `<diff-json>`: 차분 JSON 문자열을 받아 적용

## 실행 절차

### A) 열기만

1. **visualizer.html 경로를 다음 우선순위로 해석**:
   1. `$CLAUDE_PLUGIN_ROOT/skills/harness-edit/references/visualizer.html` (플러그인 모드)
   2. `$HOME/.claude/skills/harness-edit/references/visualizer.html` (셸 스크립트 설치)
   3. `$HOME/.claude/plugins/cache/*/harness-edit/*/skills/harness-edit/references/visualizer.html` (캐시 fallback)

   Bash 예시:
   ```bash
   VIS=""
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/skills/harness-edit/references/visualizer.html" ]; then
     VIS="$CLAUDE_PLUGIN_ROOT/skills/harness-edit/references/visualizer.html"
   elif [ -f "$HOME/.claude/skills/harness-edit/references/visualizer.html" ]; then
     VIS="$HOME/.claude/skills/harness-edit/references/visualizer.html"
   else
     VIS=$(ls -t $HOME/.claude/plugins/cache/*/harness-edit/*/skills/harness-edit/references/visualizer.html 2>/dev/null | head -1)
   fi
   ```

2. **OS별 열기 명령**:
   - macOS: `open "$VIS"`
   - Linux: `xdg-open "$VIS"` (실패해도 계속 진행)
   - Windows: PowerShell `Start-Process "$VIS"` 또는 `cmd /c start "" "$VIS"`

3. 「GUI 에서 편집 후, 『Claude 에 적용』 버튼의 JSON 을 붙여넣어 주세요」 라고 안내.

### B) 차분 JSON 적용

1. **파싱**. 스키마 상세는 [`references/schema.md`](references/schema.md) 를 참조.
2. **차분 미리보기를 반드시 표시** (말없이 덮어쓰지 않음):
   - add → 어느 파일에 무엇이 늘어나는지
   - remove → 무엇이 사라지는지
   - edit → from / to 를 나란히 표시
3. **위험한 변경은 AskUserQuestion 으로 재확인**:
   - deny 룰 삭제 (rm -rf 나 .env 가드 등)
   - hook script 파일 본체의 삭제
   - `CLAUDE.md` 전문 치환
4. **적용**:
   - `settings.json` / `settings.local.json` 은 Read → JSON 개변 → Write (jq 경유하지 않음)
   - hook 의 신규 `.sh` 는 템플릿을 Write 하고 `chmod +x`
   - skill / agent 의 신규는 `SKILL.md` / `<name>.md` 를 frontmatter 포함해 Write
5. **완료 보고**: 편집 파일 일람과 차분 요약을 반환하고, HTML 의 리로드를 안내.

## 안전 규칙

- **기존 파일 덮어쓰기 금지**: 동명의 skill / hook 이 있는 경우는 중지하고 다른 이름을 제안
- **적용 전에 반드시 차분 미리보기** (절차 2 에서 처리)
- 불명 target / 미대응 op 는 적용하지 않고 사용자에게 조회

## 가반성

이 스킬은 두 가지 방법으로 설치할 수 있다:
- **플러그인**: `/plugin marketplace add gaebalai/claudecode-to` → `/plugin install harness-edit@claudecode.to`. 파일은 플러그인 캐시에 저장되며 `$CLAUDE_PLUGIN_ROOT` 로 접근.
- **셸 스크립트**: `scripts/install.sh harness-edit` (macOS/Linux) 또는 `scripts/install.ps1 harness-edit` (Windows). `~/.claude/skills/harness-edit/` 로 직접 복사.

둘 다 외부 파일 의존 없는 자기완결 구성. 출력 대상(`settings.json` 등)은 항상 호출한 사용자의 `~/.claude/`.

## 예

```
사용자: {"version":1,"changes":[{"op":"add","target":"settings.permissions.allow","value":"Bash(npm *)"}]}
Claude:
  차분:
    + settings.json/permissions.allow 에 "Bash(npm *)" 를 추가
  적용하시겠습니까? (y/n)
```
