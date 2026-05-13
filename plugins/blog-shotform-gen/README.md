# blog-shotform-gen

블로그 URL 1개로 **60초 9:16 숏폼 영상(mp4)** 을 자동 생성하는 Claude Code 플러그인.

스킬 본체는 [`skills/blog-url-to-shortform/SKILL.md`](skills/blog-url-to-shortform/SKILL.md) 에 있습니다.

---

## 도구 스택

| 단계 | 도구 |
|---|---|
| 본문 추출 | Python `requests` + `BeautifulSoup` |
| 대본 생성 | Claude Code + [`shortform-script-generator`](https://github.com/) 스킬 |
| TTS (음성) | ElevenLabs REST API (`eleven_multilingual_v2`) |
| 이미지 생성 | OpenAI **gpt-image-2** (1024×1536) |
| 영상 합성 | Remotion v4 + React 19 + TypeScript |
| 영상 코덱 | H.264 + AAC (1080×1920 / 30fps) |

---

## 디렉토리 구조 (이 플러그인 안)

```
plugins/blog-shotform-gen/
├── .claude-plugin/plugin.json
├── README.md                          ← 이 파일
└── skills/blog-url-to-shortform/      ← 설치 시 ~/.claude/skills/ 로 복사됨
    ├── SKILL.md
    ├── .env.example                   ← API 키 템플릿
    └── scripts/
        ├── extract_blog.py            ← URL → JSON 본문/이미지
        ├── tts_elevenlabs.py          ← captions → mp3 컷 + 통합본
        ├── recompute_timing.py        ← ffprobe로 실측 → captions.json
        ├── gen_images.py              ← gpt-image-2 컷별 생성
        └── scaffold_remotion.py       ← Remotion 프로젝트 자동 생성
```

설치 후 스킬 위치:

```
~/.claude/skills/blog-url-to-shortform/
├── SKILL.md
├── .env                  ← 인스톨러가 입력받아 생성 (chmod 600, git ignore)
├── .env.example
└── scripts/...
```

각 실행마다 생기는 프로젝트 디렉토리:

```
~/blog-shortform-projects/<YYYYMMDD-HHMM>_<slug>/
├── extracted.json           ← URL→본문 원본
├── captions_draft.json      ← 대본 초안
├── captions.json            ← 실측 타이밍 반영
├── package.json             ← Remotion 의존성
├── src/...                  ← 자동 생성된 TS 코드
├── public/
│   ├── audio/voice.mp3      ← 통합 음성
│   ├── audio/bgm.mp3        ← (선택) BGM
│   ├── audio/cuts/*.mp3     ← 컷별 음성
│   └── images/*.png         ← 컷별 이미지
└── out/video.mp4            ← 최종 영상
```

환경 변수 `BLOG_SHORTFORM_PROJECTS_DIR` 로 프로젝트 루트를 다른 경로로 옮길 수 있습니다.

---

## 설치

루트 [`README.md`](../../README.md) 의 설치 가이드를 따르면 됩니다.

### Option A — Marketplace

```
/plugin marketplace add gaebalai/claudecode-to
/plugin install blog-shotform-gen@claudecode.to
```

호출명: `/blog-shotform-gen:blog-url-to-shortform`

### Option B — Shell 스크립트 (권장: API 키 자동 입력 후 .env 생성)

```bash
git clone https://github.com/gaebalai/claudecode-to.git
cd claudecode-to
./scripts/install.sh blog-shotform-gen
```

인스톨러가 자동으로:

1. `ffmpeg` / `ffprobe` / `python3` / `node` / `npm` 존재 확인 (macOS 는 `brew install ffmpeg` 진행 여부 prompt)
2. `requests`, `beautifulsoup4` 설치 여부 확인 (없으면 `pip install --user` prompt)
3. **ElevenLabs / OpenAI API 키 입력 prompt** → `~/.claude/skills/blog-url-to-shortform/.env` 에 chmod 600 으로 저장

대화형이 아닌 환경에서는 `.env.example` 만 복사하고 prompt 는 건너뜁니다. 강제로 건너뛰려면 `--skip-env` / `--skip-deps` 사용.

호출명: `/blog-url-to-shortform`

---

## API 키 / 환경 변수

설치 후 키를 바꾸려면 `~/.claude/skills/blog-url-to-shortform/.env` 를 직접 편집.

| 키 | 필수 | 설명 |
|---|---|---|
| `ELEVENLABS_API_KEY` | ✅ | https://elevenlabs.io/app/settings/api-keys |
| `ELEVENLABS_VOICE_A` | ✅ | Rosa Oh (한국어 여성) voice id |
| `ELEVENLABS_VOICE_B` | ✅ | Joon Park (한국어 남성) voice id |
| `ELEVENLABS_MODEL` | ❌ | 기본 `eleven_multilingual_v2` |
| `OPENAI_API_KEY` | ✅ | https://platform.openai.com/api-keys |
| `OPENAI_IMAGE_MODEL` | ❌ | 기본 `gpt-image-2` (OpenAI 측 변경 시 여기서 교체) |
| `OPENAI_IMAGE_SIZE` | ❌ | 기본 `1024x1536` (세로 2:3) |

`.env` 파일은 [.gitignore](../../.gitignore) 의 `plugins/**/.env` 패턴으로 차단되어 있어 commit 되지 않습니다.

---

## 사용 흐름

설치 후 Claude Code 에서:

```
"https://blog.naver.com/<id>/<post> 이 글로 숏폼 만들어줘"
```

Claude Code 가 자동으로 `blog-url-to-shortform` 스킬을 발동해 다음 흐름으로 진행합니다:

1. **Phase 1** — 본문 추출 → 주제 도출 → 대본 생성
2. **체크포인트 ①** 대본 OK?
3. **Phase 2.A** — 컷 1 TTS 샘플
4. **체크포인트 ②** 음성 OK?
5. **Phase 2.B** — 전체 TTS + 통합 + 타이밍 재계산
6. **Phase 2.C** — 컷 1 이미지 샘플
7. **체크포인트 ③** 이미지 OK?
8. **Phase 2.D** — 전체 이미지 (gpt-image-2)
9. **Phase 3** — Remotion 스캐폴드 + 빌드 → `out/video.mp4`

체크포인트 3번만 OK 누르면 자동으로 끝까지 진행됩니다.

---

## 시간/비용 예상 (60초 영상 1편)

| 단계 | 시간 | 비용 |
|---|---|---|
| 본문 추출 + 대본 | ~10s | 무료 |
| TTS 10컷 + 결합 | ~30s | ~300 ElevenLabs credit |
| 이미지 10컷 (gpt-image-2) | ~10min | ~$0.40 |
| Remotion 빌드 (캐시 후) | ~1min | 무료 |
| **합계** | **~12min** | **~$0.40 + 300 credit** |

---

## 선택 옵션

### BGM 깔기
`public/audio/bgm.mp3` 를 직접 두면 `scaffold_remotion.py` 가 자동으로 감지해 영상에 추가합니다 (loop, 볼륨 0.15).

### 캐릭터 일관성 강화 (reference image)
이미지 생성 시 컷 1 의 결과를 reference 로 사용해 후속 컷의 캐릭터 일관성을 높일 수 있습니다.

```bash
python3 ~/.claude/skills/blog-url-to-shortform/scripts/gen_images.py <project_dir> --cut 1
python3 ~/.claude/skills/blog-url-to-shortform/scripts/gen_images.py <project_dir> --reference-cut 1 --skip-existing
```

### 마지막 컷에 원문 URL + QR 코드
`scaffold_remotion.py` 가 마지막 컷에 원문 블로그 URL 과 QR 코드를 overlay 로 표시합니다. QR 은 외부 API (`api.qrserver.com`) 에서 빌드 시점에 1 회 다운로드.

---

## 트러블슈팅

| 증상 | 대응 |
|---|---|
| `extract_blog.py` 가 본문 500자 미만 반환 | 셀렉터 미스매치. `--debug` 옵션으로 HTML 확인 후 `scripts/extract_blog.py` 의 `PLATFORM_SELECTORS` 에 추가 |
| 네이버 블로그 추출 실패 (비공개/이웃공개) | 모바일 URL (`m.blog.naver.com`) 시도, 또는 `--naver-postview <PostView URL>` 로 직접 입력 |
| 총 길이가 60초보다 14초 이상 짧음 | 대본 일부 컷에 1~2 문장 추가 후 TTS 재호출, 또는 그대로 실측 길이 영상으로 진행 |
| `gpt-image-2` 401/404 | OpenAI 에서 모델 ID 변경된 경우. `.env` 의 `OPENAI_IMAGE_MODEL` 을 다른 ID 로 교체 |
| `npm install` 한글 경로 오류 | 프로젝트 디렉토리를 영문 경로로 이동 |
| 영상에 자막이 안 보임 | `src/data/captions.ts` 의 startSec/endSec 가 실측 음성과 매칭되는지 확인. `npm run dev` 로 Studio 띄워 디버그 |

---

## 라이선스 / 주의

- 본 워크플로는 **본인 블로그** 콘텐츠 영상화를 전제로 합니다.
- 타인 블로그 URL 을 입력하는 경우 본문/이미지 사용 권리를 직접 확인하세요.
- API 비용 (ElevenLabs, OpenAI) 은 사용자 부담입니다.
