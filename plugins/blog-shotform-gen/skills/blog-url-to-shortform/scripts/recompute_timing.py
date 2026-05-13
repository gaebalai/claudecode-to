#!/usr/bin/env python3
"""컷별 mp3 실측 길이로 captions.json 타이밍 재계산.

대본의 startSec/endSec는 초안이라 ElevenLabs 실제 출력 길이와 어긋난다.
이 스크립트는 public/audio/cuts/cut_NN.mp3 길이를 ffprobe로 재서
컷별 새 start/end를 만들어 captions.json에 쓴다.

사용 예:
    python3 recompute_timing.py <project_dir>            # gap 0.15s
    python3 recompute_timing.py <project_dir> --gap 0.2
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


def probe_duration(path: Path) -> float:
    out = subprocess.check_output(
        [
            "ffprobe", "-v", "error",
            "-show_entries", "format=duration",
            "-of", "csv=p=0",
            str(path),
        ],
        text=True,
    )
    return float(out.strip())


def main() -> int:
    p = argparse.ArgumentParser(description="ffprobe 실측 → captions.json 재작성")
    p.add_argument("project_dir")
    p.add_argument("--gap", type=float, default=0.15, help="컷 간 무음 길이(초). 기본 0.15")
    p.add_argument("--target", type=float, default=60.0, help="목표 총 길이(초). 기본 60")
    p.add_argument("--tolerance", type=float, default=3.0, help="허용 오차(초). 기본 3")
    args = p.parse_args()

    if not shutil.which("ffprobe"):
        sys.stderr.write("[error] ffprobe 미설치 (ffmpeg 패키지에 포함). brew install ffmpeg\n")
        return 4

    project = Path(args.project_dir).resolve()
    draft_path = project / "captions_draft.json"
    audio_dir = project / "public" / "audio" / "cuts"
    if not draft_path.exists():
        sys.stderr.write(f"[error] {draft_path} 없음\n")
        return 5

    draft = json.loads(draft_path.read_text(encoding="utf-8"))
    cuts = draft["captions"]

    new_cuts = []
    cursor = 0.0
    for c in cuts:
        mp3 = audio_dir / f"cut_{c['index']:02d}.mp3"
        if not mp3.exists():
            sys.stderr.write(f"[error] {mp3} 없음. tts_elevenlabs.py를 먼저 실행하세요.\n")
            return 6
        dur = probe_duration(mp3)
        start = cursor
        end = cursor + dur
        new_cuts.append({
            "index": c["index"],
            "startSec": round(start, 3),
            "endSec": round(end, 3),
            "speaker": c["speaker"],
            "text": c["text"],
            "audio": f"audio/cuts/cut_{c['index']:02d}.mp3",
            "measuredSec": round(dur, 3),
        })
        cursor = end + args.gap

    total = new_cuts[-1]["endSec"]
    delta = total - args.target

    out = {
        "source": draft["source"],
        "spec": draft["spec"],
        "totalSec": total,
        "gapSec": args.gap,
        "captions": new_cuts,
    }
    out_path = project / "captions.json"
    out_path.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")

    report = {
        "captions_path": str(out_path),
        "total_sec": round(total, 3),
        "target_sec": args.target,
        "delta_sec": round(delta, 3),
        "within_tolerance": abs(delta) <= args.tolerance,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))

    if abs(delta) > args.tolerance:
        sys.stderr.write(
            f"[warn] 총 길이 {total:.2f}s, 목표 {args.target}s 대비 {delta:+.2f}s "
            f"(허용 ±{args.tolerance}s). 사용자에게 선택 제시 필요:\n"
            "  (a) 긴 컷 텍스트 축약 후 재생성\n"
            "  (b) Remotion 총 길이를 실측값에 맞추어 진행\n"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
