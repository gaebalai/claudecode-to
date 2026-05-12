# Changelog

본 프로젝트는 [Semantic Versioning](https://semver.org/lang/ko/) 을 따릅니다.

마켓플레이스(`marketplace.json`) 의 `version` 과 각 플러그인의 `version` 은 독립적으로 관리됩니다.

## Marketplace

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
