---
name: blog-url-to-shortform
description: 블로그 URL 1개를 받아 60초 9:16 숏폼 영상(mp4)을 자동 생성하는 파이프라인. 한국 블로그 4종(티스토리/네이버/벨로그/브런치)에서 본문·이미지를 추출하고, shortform-script-generator로 2인 대화 대본을 만든 뒤, ElevenLabs TTS와 GPT Image 2(gpt-image-2)로 음성·이미지를 생성해 Remotion v4로 합성한다. "블로그 URL로 숏폼 만들어줘", "이 글로 릴스 영상 만들어줘", "blog to shortform", "blog-url-to-shortform" 같은 요청에서 발동한다.
---

# Blog URL → Shortform Video Skill

블로그 글 URL 하나만 받아서 60초 짜리 세로 숏폼 영상(mp4)을 만들어주는 **오케스트레이션 스킬**.

## 핵심 원칙

1. **사용자는 URL만 제공** — 본문·시나리오·대본·음성·이미지는 자동 생성
2. **3-Phase 점진 실행** — 무료 단계(대본)에서 사용자 승인 → 유료 단계(TTS·이미지) → 합성 단계(Remotion)
3. **기존 자산 재사용** — `shortform-script-generator` 스킬을 그대로 호출, `remotion-video-builder`의 `SpeechCaption`/`package.json` 템플릿 차용
4. **결정론적 산출물 경로** — `${BLOG_SHORTFORM_PROJECTS_DIR:-$HOME/blog-shortform-projects}/<YYYYMMDD-HHMM>_<slug>/` (기본은 `~/blog-shortform-projects/`; 사용자가 다른 경로를 지정하면 그쪽으로)
5. **유료 호출 전 확인** — TTS·이미지 생성은 항상 샘플 1개 → 사용자 승인 후 전체 진행

## 입력

| 항목 | 필수 | 비고 |
|---|---|---|
| 블로그 URL | ✅ | 티스토리/네이버/벨로그/브런치 우선 |
| 톤 | ❌ | 기본: 친근한 한국어 구어체 |
| 화자 | ❌ | 기본: Rosa Oh (30대 여성, 리드) + Joon Park (20대 후반 남성, 리액션) |
| 길이 | ❌ | 기본 60초 |

## 환경 변수 (`.env`)

스킬 디렉토리 `~/.claude/skills/blog-url-to-shortform/.env`에 보관. 누락 시 Phase 2 진입 전에 즉시 중단하고 사용자에게 안내.

```
ELEVENLABS_API_KEY=...
ELEVENLABS_VOICE_A=...   # 화자 A (Rosa Oh, 한국어 여성 voice id)
ELEVENLABS_VOICE_B=...   # 화자 B (Joon Park, 한국어 남성 voice id)
OPENAI_API_KEY=...
```

`.env.example`을 그대로 복사해서 채우면 됨.

## 의존성

- Python 3.10+ (3.14 검증됨) + `pip install requests beautifulsoup4`
  - `.env`는 인라인 파서로 처리(`python-dotenv` 불필요)
  - OpenAI/ElevenLabs는 SDK 대신 `requests`로 REST 직접 호출
- ffmpeg + ffprobe (Phase 2 mp3 결합 / 길이 측정) — `brew install ffmpeg`
- Node.js v20 LTS 이상 (Phase 3 Remotion 빌드) — v25에서도 동작

## Phase 1 — URL → 대본 (무료, 빠름)

### Step 1.1: URL 입력 받기
사용자가 URL 하나를 던지면 시작. 형식 검증(http/https로 시작).

### Step 1.2: 본문 추출
```bash
python3 ~/.claude/skills/blog-url-to-shortform/scripts/extract_blog.py "<URL>" \
    > <project_dir>/extracted.json
```
- stdout이 JSON. 키 `{platform, url, title, body, body_images, char_count}`
- **반드시 프로젝트 디렉토리에 `extracted.json`으로 저장** (Phase 2 Step 2.6에서 본문 이미지 substitute에 사용)
- 플랫폼 자동 감지: 도메인 매칭(`tistory.com`, `blog.naver.com`/`m.blog.naver.com`, `velog.io`, `brunch.co.kr`)
- 네이버는 iframe 재요청을 자동 처리
- 본문이 500자 미만이면 경고 메시지

### Step 1.3: 본문 요약 → 주제·핵심 포인트
Claude가 직접 수행. 추출된 `title`/`body`를 보고:
- **주제** (한 줄, 시청자 후크용)
- **핵심 포인트 3개** (각 1문장, 본론에서 다룰 내용)
- **반전/CTA 후보** (마지막 컷에 쓸 메시지)

### Step 1.4: `shortform-script-generator` 호출
`Skill` 도구로 `shortform-script-generator`를 호출하면서 다음을 전달:
- 주제: Step 1.3에서 도출한 한 줄
- 총 길이: 60초
- 컷 수: 10
- 화자 A: "Rosa Oh (30대 여성, 자신감 있는 리드)"
- 화자 B: "Joon Park (20대 후반 남성, 질문/리액션)"
- 언어: ko
- 추가 컨텍스트:
  - Step 1.3의 핵심 포인트 3개를 본론(30~70%)에 녹이도록 요청
  - **각 컷의 한국어 텍스트는 25~30자 안으로 작성** — 한국어 ElevenLabs voice가 영문/일문 대비 빨라서, 짧은 컷이 누적되면 60초가 안 채워지는 경향이 있음. 25~30자/컷이 발화 약 6초/컷에 매칭되어 자막 가독성과 총 길이 모두를 잡음
  - 컷 사이 자연스러운 호흡(0.15초 무음)이 들어가도 60초에 맞도록, 총 발화 합계는 약 55~58초가 되도록 분배 권장

### Step 1.5: 대본 표 파싱 → `captions_draft.json`
`shortform-script-generator`가 반환한 마크다운 표(`# | 시간 | 캐릭터 | 대사`)와 `CAPTIONS` 배열을 매핑하여 speaker 보강:

```json
[
  {"index": 1, "startSec": 0.0, "endSec": 6.0, "speaker": "A", "text": "..."},
  {"index": 2, "startSec": 6.12, "endSec": 11.21, "speaker": "B", "text": "..."}
]
```

이 JSON을 프로젝트 디렉토리 `~/blog-shortform-projects/<YYYYMMDD-HHMM>_<slug>/captions_draft.json` (또는 `$BLOG_SHORTFORM_PROJECTS_DIR` 로 지정된 경로) 에 저장. 디렉토리가 없으면 함께 생성.

### Step 1.6: 사용자 체크포인트
대본 표를 그대로 보여주고 다음 질문을 던짐:
- 첫 컷이 스크롤 스토퍼로 충분한지
- 톤이 적절한지
- 핵심 포인트가 잘 들어갔는지

수정 요청 시 해당 컷만 다시 작성. 승인되면 Phase 2 진입.

## Phase 2 — TTS + 이미지 (유료, 중간 속도)

`captions_draft.json`을 입력으로 ElevenLabs TTS + gpt-image-2를 호출해 `public/audio/voice.mp3`와 `public/images/cut_NN.png`를 채운다.

### Step 2.1: 환경 검증
- `~/.claude/skills/blog-url-to-shortform/.env`에 4개 키가 모두 채워졌는지 확인
- `which ffmpeg && which ffprobe` 확인 (없으면 `brew install ffmpeg`)
- 둘 중 하나라도 부족하면 사용자에게 안내하고 즉시 중단

### Step 2.2: TTS 샘플 확인
유료 API라 전체 호출 전에 샘플 1컷으로 voice id가 의도와 맞는지 확인:
```bash
python3 ~/.claude/skills/blog-url-to-shortform/scripts/tts_elevenlabs.py <project_dir> --cut 1
```
출력된 `public/audio/cuts/cut_01.mp3`를 사용자에게 안내(QuickLook으로 재생 가능). 음성 OK가 떨어지면 다음 단계.

### Step 2.3: 전체 TTS 생성
```bash
python3 ~/.claude/skills/blog-url-to-shortform/scripts/tts_elevenlabs.py <project_dir>
```
- 컷별 mp3가 `public/audio/cuts/cut_NN.mp3`로 저장
- 통합본 `public/audio/voice.mp3` 자동 결합 (ffmpeg concat, 컷 간 무음 0.15초)

### Step 2.4: 타이밍 재계산
```bash
python3 ~/.claude/skills/blog-url-to-shortform/scripts/recompute_timing.py <project_dir>
```
- `captions.json` 생성 (실측 startSec/endSec + audio 경로)
- 총 길이 60초 ±3초 안이면 그대로 진행
- 벗어나면 stderr에 경고. 사용자에게 (a) 긴 컷 텍스트 축약 재생성 (b) Remotion duration을 실측값으로 사용 중 택일을 제시

### Step 2.5: 이미지 샘플 확인
```bash
python3 ~/.claude/skills/blog-url-to-shortform/scripts/gen_images.py <project_dir> --cut 1
```
- `public/images/cut_01.png` 생성. 스타일이 의도와 맞는지 사용자가 확인
- Rosa Oh/Joon Park 캐릭터 일관성은 보장 못 함 — 스타일(색조·구도) 일관성만 확인

### Step 2.6: 전체 이미지 생성
```bash
python3 ~/.claude/skills/blog-url-to-shortform/scripts/gen_images.py <project_dir> \
    --substitute 3,6,9 --blog-images <project_dir>/extracted.json
```
- 컷 3·6·9는 블로그 본문 이미지로 대체(다양성 + 캐릭터 일관성 부담 줄임)
- 나머지 컷은 gpt-image-2 신규 생성
- `--blog-images`는 Phase 1에서 저장해둔 `extracted.json` 또는 본문 이미지 URL 배열 JSON

### Step 2.7: Phase 2 산출물 점검
프로젝트 디렉토리에 다음이 모두 존재해야 함:
```
projects/<run>/
├── captions_draft.json      (Phase 1)
├── extracted.json           (Phase 1, body_images 포함)
├── captions.json            (Step 2.4)
└── public/
    ├── audio/
    │   ├── voice.mp3        (Step 2.3)
    │   └── cuts/cut_NN.mp3  (Step 2.3)
    └── images/cut_NN.png    (Step 2.6)
```

## Phase 3 — Remotion 합성 (느림, 무료)

`captions.json` + `public/audio/voice.mp3` + `public/images/cut_NN.png`가 모두 준비됐다면 Remotion v4 프로젝트를 결정론적으로 생성해 mp4로 렌더한다.

### Step 3.1: 스캐폴드
```bash
python3 ~/.claude/skills/blog-url-to-shortform/scripts/scaffold_remotion.py <project_dir>
```
- 1080×1920 / 30fps / Composition id `BlogShortform`
- 생성되는 파일:
  - `package.json` (Remotion v4 + React 19 + TS5)
  - `tsconfig.json`, `remotion.config.ts`
  - `src/index.ts`, `src/Root.tsx`
  - `src/data/scenes.ts` (FPS·WIDTH·HEIGHT·TOTAL_SEC·VOICE_FILE)
  - `src/data/captions.ts` (Caption[] — startSec/endSec/text/speaker/image)
  - `src/components/SpeechCaption.tsx` (Pretendard fallback, 외곽선)
  - `src/compositions/BlogShortform.tsx` (KenBurnsImg + Audio + Sequence × N)
- 자산 누락 시 즉시 중단 (Phase 2가 완료돼 있어야 함)

### Step 3.2: 의존성 설치
```bash
cd <project_dir>
npm install --prefer-offline --no-audit --no-fund
```
- 첫 실행은 ~470MB, 1~3분. 2회차부터는 npm 캐시 덕분에 수초 안에 끝남
- Node v20 LTS 이상 (v25에서도 검증됨)

### Step 3.3: 렌더
```bash
npm run build
```
- `out/video.mp4` 생성. 45초 영상 기준 약 1분 (M-series Mac)
- H.264 / AAC 48kHz / 1080×1920 / 30fps

### Step 3.4: 검증
```bash
ffprobe -v error -show_entries format=duration,size:stream=codec_name,width,height,r_frame_rate \
        -of default <project_dir>/out/video.mp4
```
- 길이가 `captions.json`의 `totalSec`와 ±0.1초 안인지
- 1080×1920, 30fps, h264/aac 모두 정상인지
- macOS QuickLook(스페이스바)으로 자막·음성 동기 확인

### Step 3.5: 미리보기/수정 (선택)
```bash
npm run dev   # Remotion Studio (브라우저 GUI)
```
자막 타이밍 미세 조정이 필요하면 `src/data/captions.ts`의 startSec/endSec만 손보고 다시 `npm run build`.

## 사용자와의 대화 패턴

**사용자**: `https://tistory.com/example/blog-post 이 글로 숏폼 만들어줘`

**Claude의 응답 흐름**:
1. URL 확인 + Phase 1 시작 안내
2. `extract_blog.py` 실행 → 제목·본문 글자수·본문 이미지 N장 요약 + `extracted.json` 저장
3. 본문 요약 → 주제·핵심 포인트 3개 제시
4. `shortform-script-generator` 호출 → 대본 표 출력
5. **체크포인트 ①**: 대본 OK? 컷 수정 요청 있으면 해당 컷만 재작성
6. `.env` 검증 → ffmpeg/ffprobe 확인
7. `tts_elevenlabs.py --cut 1` → **체크포인트 ②** 음성 톤 OK?
8. 전체 TTS → `recompute_timing.py` → 총 길이가 60초 ±3초 안인지 보고
9. `gen_images.py --cut 1` → **체크포인트 ③** 이미지 스타일 OK?
10. 전체 이미지 (`--skip-existing`로 컷 1 재생성 회피, 필요시 `--substitute`)
11. `scaffold_remotion.py` → `npm install` → `npm run build` (필요 시 background)
12. ffprobe로 최종 mp4 검증 후 절대 경로 보고

## 금지 사항

- 사용자 승인 없이 ElevenLabs/OpenAI API를 호출하지 않음 (Phase 2 미구현 시 절대 호출 X)
- 타인 블로그 URL이 입력되면 본문 이미지를 영상에 그대로 쓰지 않고 인용 표시를 권장
- 본문 추출 실패 시 빈 대본을 만들지 말고 즉시 중단하여 사용자에게 URL을 재확인 요청
- `~/.claude/skills/blog-url-to-shortform/.env`는 절대 commit하거나 화면에 출력하지 않음 (값 노출 금지)

## 트러블슈팅

| 증상 | 대응 |
|---|---|
| `extract_blog.py`가 본문 500자 미만 반환 | 셀렉터가 안 맞은 것. `--debug` 옵션으로 raw HTML 확인 후 셀렉터 보강 |
| 네이버 블로그 추출 실패 | iframe URL 직접 입력 옵션: `python3 extract_blog.py --naver-postview "<PostView URL>"` |
| `shortform-script-generator`의 컷이 너무 많거나 적음 | 호출 시 `컷 수 10`을 명시. 결과가 어긋나면 사용자에게 보고 후 재요청 |
| Phase 2 진입 전 `.env` 누락 | 안내 메시지 출력 후 중단. 자동 호출 시도 금지 |
