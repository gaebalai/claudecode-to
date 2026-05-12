# claudecode.to

Claude Code 생산성 플러그인 모음 — Marketplace 레포.

이 레포는 [Claude Code 플러그인 마켓플레이스](https://code.claude.com/docs/en/plugin-marketplaces.md) 입니다. 여러 개의 플러그인을 한 곳에서 호스팅하며, 각 플러그인은 독립적으로 설치·업데이트할 수 있습니다.

## 수록 플러그인

| 플러그인 | 설명 |
|---|---|
| [harness-edit](plugins/harness-edit/) | `.claude` 하네스 설정을 시각화 HTML 로 직관적으로 편집. GUI 에서 만든 차분 JSON 을 받아 `settings.json` 등에 안전하게 반영. |
| [ui-style-lab](plugins/ui-style-lab/) | UI 스타일 비교용 단일 HTML 생성기. 프리셋 10 종 / 색 / 폰트 / 형상을 즉시 전환하고, 컴포넌트 클릭으로 코드를 복사. |

앞으로 다른 플러그인도 같은 레포에 `plugins/<name>/` 로 추가됩니다.

---

## 설치 — Option A: Marketplace (권장)

Claude Code 안에서:

```
/plugin marketplace add gaebalai/claudecode-to
/plugin install harness-edit@claudecode.to
/plugin install ui-style-lab@claudecode.to
```

호출 명령:

```
/harness-edit:harness-edit
/ui-style-lab:ui-style-lab
```

업데이트:

```
/plugin marketplace update claudecode.to
/plugin update harness-edit@claudecode.to
```

제거:

```
/plugin uninstall harness-edit@claudecode.to
```

---

## 설치 — Option B: Shell script

`~/.claude/skills/` 에 직접 복사하는 방식입니다. standalone 호출명(`/harness-edit`, `/ui-style-lab`)을 그대로 쓸 수 있습니다.

### macOS / Linux

```bash
git clone https://github.com/gaebalai/claudecode-to.git
cd claudecode-to
./scripts/install.sh                 # 사용 가능한 플러그인 목록 출력
./scripts/install.sh harness-edit    # 하나만 설치
./scripts/install.sh --all           # 전부 설치
./scripts/install.sh harness-edit --backup   # 기존 디렉토리는 자동 백업
```

### Windows (PowerShell 5.1+)

```powershell
git clone https://github.com/gaebalai/claudecode-to.git
cd claudecode-to
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Plugin harness-edit
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -All
```

### 옵션 공통

| Bash | PowerShell | 동작 |
|---|---|---|
| `--all` | `-All` | 모든 플러그인 설치 |
| `--force` | `-Force` | 기존 디렉토리 묻지 않고 덮어씀 |
| `--backup` | `-Backup` | 기존을 `<name>.bak.YYYYMMDD-HHMMSS` 로 백업 |
| `--dry-run` | `-DryRun` | 실제 변경 없이 동작만 출력 |
| `--symlink` | `-Symlink` | 복사 대신 심볼릭 링크 (개발자용; Windows 는 관리자/개발자 모드 필요) |

환경 변수 `CLAUDE_HOME` 으로 `~/.claude` 위치를 재정의할 수 있습니다.

### 제거

```bash
./scripts/uninstall.sh                # 사용 가능한 플러그인 목록 출력
./scripts/uninstall.sh harness-edit   # 하나만 제거
./scripts/uninstall.sh --all          # 전부 제거
./scripts/uninstall.sh harness-edit --yes  # 확인 없이
```

---

## 호출명 대조표

| 모드 | harness-edit | ui-style-lab |
|---|---|---|
| **Plugin** (Option A) | `/harness-edit:harness-edit` | `/ui-style-lab:ui-style-lab` |
| **Standalone** (Option B) | `/harness-edit` | `/ui-style-lab` |

두 모드를 동시에 설치해도 namespace 가 달라 충돌하지 않습니다.

---

## 검증

설치 직후:

```
/plugin marketplace list          # claudecode.to 가 active 여야 함
/plugin list                       # 설치한 플러그인이 active 여야 함
```

또는 standalone 모드:

```bash
ls ~/.claude/skills/
```

세션을 새로 열거나 `/reload-skills` 후 호출 명령을 실행해 봅니다.

---

## 디렉토리 구조

```
claudecode-to/                              # marketplace repo root
├── .claude-plugin/
│   └── marketplace.json                    # 마켓플레이스 카탈로그
├── plugins/
│   ├── harness-edit/                       # 플러그인 1
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/harness-edit/
│   │       ├── SKILL.md
│   │       └── references/{visualizer.html, schema.md}
│   └── ui-style-lab/                       # 플러그인 2
│       ├── .claude-plugin/plugin.json
│       └── skills/ui-style-lab/
│           ├── SKILL.md
│           └── template.html
├── scripts/
│   ├── install.sh
│   ├── install.ps1
│   └── uninstall.sh
├── README.md
├── LICENSE
├── CHANGELOG.md
└── .gitignore
```

---

## 새 플러그인 추가하는 법

1. `plugins/<new-plugin-name>/` 디렉토리 생성
2. `plugins/<new-plugin-name>/.claude-plugin/plugin.json` 작성 (name / description / version / author / license)
3. `plugins/<new-plugin-name>/skills/<skill-name>/SKILL.md` 작성 (그리고 필요한 리소스)
4. 루트의 `.claude-plugin/marketplace.json` 의 `plugins[]` 배열에 새 항목 추가:
   ```json
   {
     "name": "<new-plugin-name>",
     "source": "./plugins/<new-plugin-name>",
     "description": "...",
     "category": "productivity",
     "tags": ["..."]
   }
   ```
5. `CHANGELOG.md` 에 새 플러그인 추가 항목 기록
6. `git commit && git push`

`install.sh`, `install.ps1`, `uninstall.sh` 는 `plugins/` 디렉토리를 자동 스캔하므로 별도 수정 불필요합니다.

---

## License

[MIT](LICENSE)

각 플러그인의 SKILL.md 본문에 적힌 사용법·인자 상세는 해당 플러그인 디렉토리(`plugins/<name>/skills/<name>/SKILL.md`) 를 직접 참조하세요.
