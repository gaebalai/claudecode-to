# Changelog

본 프로젝트는 [Semantic Versioning](https://semver.org/lang/ko/) 을 따릅니다.

마켓플레이스(`marketplace.json`) 의 `version` 과 각 플러그인의 `version` 은 독립적으로 관리됩니다.

## Marketplace

### [1.1.0] - 2026-05-13
- `blog-shotform-gen` 플러그인 추가. 블로그 URL 1개 → 60초 9:16 mp4 자동 생성 파이프라인.
- `scripts/install.sh` / `scripts/install.ps1`:
  - 플러그인별 post-install 후크 추가.
  - `blog-shotform-gen` 설치 시 ffmpeg/ffprobe/python/node 의존성 체크 + `requests`, `beautifulsoup4` 자동 설치 옵션.
  - `ELEVENLABS_*` / `OPENAI_*` API 키를 인터랙티브하게 입력받아 `~/.claude/skills/blog-url-to-shortform/.env` 에 chmod 600 으로 저장.
  - 새 옵션 `--skip-env` / `--skip-deps` (Bash), `-SkipEnv` / `-SkipDeps` (PowerShell).
- README 의 플러그인 목록·옵션 표·디렉토리 구조 갱신.

### [1.0.0] - 2026-05-12
- 단일 플러그인 → multi-plugin marketplace 레이아웃으로 재구성.
- `harness-edit` 와 `ui-style-lab` 을 각각 독립 플러그인으로 분리.
- 디렉토리 구조 변경:
  - `skills/<name>/` → `plugins/<name>/skills/<name>/`
  - 각 플러그인에 자체 `.claude-plugin/plugin.json` 부여
- `scripts/install.sh`, `install.ps1`, `uninstall.sh` 를 plugin-name 인수 + `--all` 옵션 형태로 재작성.
- 호출명 변경:
  - 플러그인 모드: `/claude-skills-html-pair:harness-edit` → `/harness-edit:harness-edit`
  - 플러그인 모드: `/claude-skills-html-pair:ui-style-lab` → `/ui-style-lab:ui-style-lab`
  - standalone 호출명 (`/harness-edit`, `/ui-style-lab`) 은 동일.
- SKILL.md 본문의 플러그인 캐시 fallback 경로 패턴을 새 구조에 맞게 갱신.
- README 를 multi-plugin marketplace 관점으로 다시 작성하고 "새 플러그인 추가하는 법" 가이드 추가.

### [0.1.0] - 2026-05-12 (초기)
- 단일 플러그인 `claude-skills-html-pair` 로 두 스킬 묶음 패키징.
- macOS/Linux/Windows 용 인스톨러·언인스톨러 스크립트.

## Plugins

### `harness-edit` v2.0.0 — 2026-05-12
- 마켓플레이스 분리 후 첫 독립 릴리스.

### `ui-style-lab` v1.1.0 — 2026-05-12
- 마켓플레이스 분리 후 첫 독립 릴리스.

### `blog-shotform-gen` v1.0.0 — 2026-05-13
- 신규 플러그인. 블로그 URL 1개를 받아 60초 세로 숏폼 영상(mp4)을 자동 생성.
- 한국 블로그 4종(티스토리/네이버/벨로그/브런치) 본문·이미지 추출 → 2인 대화 대본 → ElevenLabs TTS + GPT Image 2 → Remotion v4 합성.
- `~/.claude/skills/blog-url-to-shortform/.env` 에 API 키 보관 (인스톨러가 생성).
