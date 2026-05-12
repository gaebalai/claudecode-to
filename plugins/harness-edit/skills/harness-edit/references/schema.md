# harness-edit — 차분 JSON 스키마 상세

`/harness-edit <diff-json>` 이 받는 JSON 의 완전 사양. SKILL.md 에서는 이 reference 를 참조한다.

## 톱 레벨

```json
{
  "version": 1,
  "changes": [ { "op": "...", "target": "...", ... } ]
}
```

## target × op 매트릭스

| target                             | op                  | 처리                                                                                                                                                                      |
| ---------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `settings.env`                     | add/remove/edit     | `settings.json` 의 `env` 를 편집                                                                                                                                          |
| `settings.permissions.allow`       | add/remove          | `settings.json` 의 allow 배열을 편집                                                                                                                                      |
| `settings.permissions.deny`        | add/remove          | `settings.json` 의 deny 배열을 편집                                                                                                                                       |
| `settings.hooks`                   | add/remove/edit     | `settings.json` 의 hooks 를 편집 + 필요하면 `hooks/*.sh` 템플릿을 생성                                                                                                    |
| `settings.plugins`                 | add/remove          | `enabledPlugins` 를 편집                                                                                                                                                  |
| `settings.<key>`                   | edit                | 임의 톱 레벨 키 (model / theme / editorMode / preferredNotifChannel / worktree.baseRef / attribution / voice.enabled 등). 닷 표기법 가능. `to` 가 빈 값/null/false 면 삭제 |
| `settings-local.permissions.allow` | add/remove          | `settings.local.json` 의 allow                                                                                                                                            |
| `settings-local.enabledPlugins`    | add/remove/edit     | `settings.local.json` 의 enabledPlugins                                                                                                                                   |
| `CLAUDE.md`                        | edit (mode=replace) | 전문 치환 (`to` 에 새 본문)                                                                                                                                               |
| `skills`                           | add/remove          | `skills/<name>/SKILL.md` 생성/삭제                                                                                                                                        |
| `agents`                           | add/remove          | `agents/<name>.md` 생성/삭제                                                                                                                                              |

## 페이로드 예

### hooks 추가

```json
{
  "op": "add",
  "target": "settings.hooks",
  "event": "PostToolUse",
  "matcher": "Bash",
  "command": "~/.claude/hooks/my-hook.sh",
  "scriptName": "my-hook.sh",
  "scriptBody": "#!/bin/bash\n..."
}
```

→ `settings.json` 의 `hooks.PostToolUse[].hooks[]` 에 추가. `scriptName` 지정 시는 `hooks/<name>.sh` 생성 + `chmod +x`.

### hooks 삭제

```json
{
  "op": "remove",
  "target": "settings.hooks",
  "event": "PostToolUse",
  "scriptName": "my-hook.sh"
}
```

→ settings.json 에서 삭제. `hooks/<name>.sh` 본체 삭제는 **반드시 AskUserQuestion 으로 확인**.

### permissions

```json
{ "op": "add",    "target": "settings.permissions.allow", "value": "Bash(npm *)" }
{ "op": "remove", "target": "settings.permissions.deny",  "value": "Bash(rm -rf .*)" }
```

### env

```json
{ "op": "add",  "target": "settings.env", "key": "FOO", "value": "bar" }
{ "op": "edit", "target": "settings.env", "key": "FOO", "from": "bar", "to": "baz" }
```

### skill / agent 추가

```json
{
  "op": "add",
  "target": "skills",
  "name": "my-skill",
  "description": "짧은 설명 + TRIGGER when: ...",
  "body": "# /my-skill\n\n본체 마크다운"
}
```

→ `skills/<name>/SKILL.md` 를 frontmatter 포함해 생성.

## hook 이벤트 일람 (공식 docs 준거·전 29 종)

SessionStart / SessionEnd / Setup / UserPromptSubmit / UserPromptExpansion / PreToolUse / PermissionRequest / PermissionDenied / PostToolUse / PostToolUseFailure / PostToolBatch / Notification / SubagentStart / SubagentStop / TaskCreated / TaskCompleted / Stop / StopFailure / TeammateIdle / InstructionsLoaded / ConfigChange / CwdChanged / FileChanged / WorktreeCreate / WorktreeRemove / PreCompact / PostCompact / Elicitation / ElicitationResult

**matcher 불가 (10 종)**: UserPromptSubmit / PostToolBatch / TaskCreated / TaskCompleted / Stop / TeammateIdle / CwdChanged / WorktreeCreate / WorktreeRemove

나머지는 matcher 지정 가능.
