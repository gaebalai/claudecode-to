#!/usr/bin/env python3
"""captions_draft.json → 컷별 mp3 + 통합 voice.mp3.

ElevenLabs `/v1/text-to-speech/{voice_id}` REST 호출(공식 SDK 미사용).
화자 A/B는 .env의 ELEVENLABS_VOICE_A/B로 매핑.
결합은 ffmpeg `-f concat -c copy`로 무손실 이어붙임.

사용 예:
    python3 tts_elevenlabs.py <project_dir>           # captions_draft.json 사용
    python3 tts_elevenlabs.py <project_dir> --cut 1   # 특정 컷만 (샘플 확인용)
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

try:
    import requests
except ImportError as e:
    sys.stderr.write(f"[error] 의존성 누락: {e}\n  pip install requests\n")
    sys.exit(2)


SKILL_DIR = Path(__file__).resolve().parent.parent
ENV_PATH = SKILL_DIR / ".env"
ELEVEN_BASE = "https://api.elevenlabs.io/v1/text-to-speech"


def load_dotenv_simple(path: Path) -> None:
    """KEY=VALUE 한 줄씩 파싱. # 주석·빈 줄 무시. 따옴표 한 겹 제거."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        k = k.strip()
        v = v.strip()
        if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
            v = v[1:-1]
        if k and k not in os.environ:
            os.environ[k] = v


def load_env() -> dict:
    if not ENV_PATH.exists():
        sys.stderr.write(
            f"[error] {ENV_PATH} 가 없습니다.\n"
            f"  cp {SKILL_DIR}/.env.example {ENV_PATH}\n"
            "  이후 ELEVENLABS_API_KEY / VOICE_A / VOICE_B 를 채워주세요.\n"
        )
        sys.exit(3)
    load_dotenv_simple(ENV_PATH)
    keys = ["ELEVENLABS_API_KEY", "ELEVENLABS_VOICE_A", "ELEVENLABS_VOICE_B"]
    env = {k: os.environ.get(k, "").strip() for k in keys}
    missing = [k for k, v in env.items() if not v]
    if missing:
        sys.stderr.write(f"[error] .env 누락 키: {', '.join(missing)}\n")
        sys.exit(3)
    env["ELEVENLABS_MODEL"] = os.environ.get("ELEVENLABS_MODEL", "eleven_multilingual_v2")
    return env


def synth_one(text: str, voice_id: str, api_key: str, model: str, out_path: Path) -> None:
    url = f"{ELEVEN_BASE}/{voice_id}"
    payload = {
        "text": text,
        "model_id": model,
        "voice_settings": {"stability": 0.5, "similarity_boost": 0.75, "style": 0.0, "use_speaker_boost": True},
    }
    headers = {
        "xi-api-key": api_key,
        "accept": "audio/mpeg",
        "content-type": "application/json",
    }
    r = requests.post(url, json=payload, headers=headers, timeout=60)
    if r.status_code != 200:
        sys.stderr.write(f"[elevenlabs] {r.status_code} {r.text[:300]}\n")
        r.raise_for_status()
    out_path.write_bytes(r.content)


def concat_mp3(parts: list[Path], out_path: Path, gap_sec: float = 0.15) -> None:
    if not shutil.which("ffmpeg"):
        sys.stderr.write("[error] ffmpeg 미설치. brew install ffmpeg\n")
        sys.exit(4)

    work = out_path.parent
    silence = work / "_gap.mp3"
    if gap_sec > 0:
        subprocess.run(
            [
                "ffmpeg", "-y", "-f", "lavfi", "-i",
                f"anullsrc=channel_layout=mono:sample_rate=44100",
                "-t", f"{gap_sec}", "-q:a", "9", "-acodec", "libmp3lame",
                str(silence),
            ],
            check=True, capture_output=True,
        )

    listfile = work / "_concat.txt"
    lines: list[str] = []
    for i, p in enumerate(parts):
        lines.append(f"file '{p.as_posix()}'")
        if gap_sec > 0 and i < len(parts) - 1:
            lines.append(f"file '{silence.as_posix()}'")
    listfile.write_text("\n".join(lines), encoding="utf-8")

    subprocess.run(
        ["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(listfile), "-c", "copy", str(out_path)],
        check=True, capture_output=True,
    )

    listfile.unlink(missing_ok=True)
    silence.unlink(missing_ok=True)


def main() -> int:
    p = argparse.ArgumentParser(description="ElevenLabs TTS — captions_draft.json → mp3")
    p.add_argument("project_dir", help="captions_draft.json이 있는 프로젝트 디렉토리")
    p.add_argument("--cut", type=int, help="특정 컷 번호만 생성 (샘플 확인용)")
    p.add_argument("--gap", type=float, default=0.15, help="컷 사이 무음 길이(초). 기본 0.15")
    args = p.parse_args()

    env = load_env()
    project = Path(args.project_dir).resolve()
    draft_path = project / "captions_draft.json"
    if not draft_path.exists():
        sys.stderr.write(f"[error] {draft_path} 없음. Phase 1을 먼저 실행하세요.\n")
        return 5

    draft = json.loads(draft_path.read_text(encoding="utf-8"))
    cuts = draft["captions"]
    voice_map = {"A": env["ELEVENLABS_VOICE_A"], "B": env["ELEVENLABS_VOICE_B"]}

    audio_dir = project / "public" / "audio" / "cuts"
    audio_dir.mkdir(parents=True, exist_ok=True)

    targets = [c for c in cuts if (args.cut is None or c["index"] == args.cut)]
    if not targets:
        sys.stderr.write(f"[error] 컷 #{args.cut} 없음\n")
        return 6

    generated: list[Path] = []
    for c in targets:
        idx = c["index"]
        speaker = c["speaker"]
        text = c["text"]
        voice = voice_map[speaker]
        out = audio_dir / f"cut_{idx:02d}.mp3"
        sys.stderr.write(f"[tts] #{idx} ({speaker}) → {out.name} ({len(text)}자)\n")
        synth_one(text, voice, env["ELEVENLABS_API_KEY"], env["ELEVENLABS_MODEL"], out)
        generated.append(out)

    if args.cut is None:
        merged = project / "public" / "audio" / "voice.mp3"
        sys.stderr.write(f"[tts] 통합 → {merged} (gap={args.gap}s)\n")
        concat_mp3(generated, merged, gap_sec=args.gap)
        print(json.dumps({"merged": str(merged), "count": len(generated)}, ensure_ascii=False))
    else:
        print(json.dumps({"sample": str(generated[0])}, ensure_ascii=False))

    return 0


if __name__ == "__main__":
    sys.exit(main())
