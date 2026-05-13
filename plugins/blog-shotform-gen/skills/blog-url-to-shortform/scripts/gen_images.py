#!/usr/bin/env python3
"""captions.json → 컷별 이미지 (gpt-image-2, 1024×1536, 세로 2:3).

스타일 통일을 위해 컷별 프롬프트에 공통 접미사를 붙인다(캐릭터 일관성 100%는 보장 못 함).
substitute 옵션: 블로그 본문 이미지를 일부 컷에 끼워 다양성을 더한다.

사용 예:
    python3 gen_images.py <project_dir>                 # 전체 컷 생성
    python3 gen_images.py <project_dir> --cut 1         # 컷 1만 (샘플)
    python3 gen_images.py <project_dir> --substitute 3,6,9 --blog-images extracted.json
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
from pathlib import Path
from typing import Optional

try:
    import requests
except ImportError as e:
    sys.stderr.write(f"[error] 의존성 누락: {e}\n  pip install requests\n")
    sys.exit(2)


SKILL_DIR = Path(__file__).resolve().parent.parent
ENV_PATH = SKILL_DIR / ".env"


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

STYLE_SUFFIX = (
    "flat 2D illustration, soft pastel palette, vertical 9:16 composition, "
    "korean female character Rosa Oh with warm peach tones, "
    "korean male character Joon Park with cool blue tones, "
    "consistent line weight, gentle shading, no text, no captions, no watermark"
)


def load_env() -> dict:
    if not ENV_PATH.exists():
        sys.stderr.write(f"[error] {ENV_PATH} 없음. .env.example을 복사해 채우세요.\n")
        sys.exit(3)
    load_dotenv_simple(ENV_PATH)
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key:
        sys.stderr.write("[error] OPENAI_API_KEY가 비어있습니다.\n")
        sys.exit(3)
    return {
        "OPENAI_API_KEY": key,
        "OPENAI_IMAGE_MODEL": os.environ.get("OPENAI_IMAGE_MODEL", "gpt-image-2"),
        "OPENAI_IMAGE_SIZE": os.environ.get("OPENAI_IMAGE_SIZE", "1024x1536"),
    }


def build_prompt(cut: dict) -> str:
    speaker_name = "Rosa Oh" if cut["speaker"] == "A" else "Joon Park"
    scene = cut["text"]
    return (
        f"Scene for a short vertical video, speaker {speaker_name} delivering this line: "
        f"\"{scene}\". Show the speaker as the main subject with a relevant visual metaphor "
        f"of the line in the background. {STYLE_SUFFIX}"
    )


def _decode_image_response(resp_data: dict) -> bytes:
    if "b64_json" in resp_data:
        return base64.b64decode(resp_data["b64_json"])
    if "url" in resp_data:
        return requests.get(resp_data["url"], timeout=60).content
    raise RuntimeError("응답에 b64_json/url 둘 다 없음")


# 5xx + 429만 재시도. 4xx(인증·요청 오류)는 즉시 실패시켜 토큰 낭비 방지.
_RETRY_STATUSES = {429, 500, 502, 503, 504}


def _request_with_retry(method: str, url: str, *, label: str, max_retries: int = 4, **kwargs):
    last_resp = None
    for attempt in range(1, max_retries + 1):
        try:
            r = requests.request(method, url, **kwargs)
            if r.status_code not in _RETRY_STATUSES:
                return r
            last_resp = r
            sys.stderr.write(f"[retry {attempt}/{max_retries}] {label} → HTTP {r.status_code}\n")
        except requests.RequestException as e:
            last_resp = None
            sys.stderr.write(f"[retry {attempt}/{max_retries}] {label} → {type(e).__name__}: {e}\n")
        if attempt < max_retries:
            time.sleep(min(60, 4 * (2 ** (attempt - 1))))  # 4s, 8s, 16s, 32s (cap 60)
    if last_resp is not None:
        return last_resp
    raise RuntimeError(f"{label}: 모든 재시도 실패")


def call_gpt_image(prompt: str, api_key: str, model: str, size: str) -> bytes:
    r = _request_with_retry(
        "POST",
        "https://api.openai.com/v1/images/generations",
        label="images/generations",
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        json={"model": model, "prompt": prompt, "n": 1, "size": size},
        timeout=180,
    )
    if r.status_code != 200:
        sys.stderr.write(f"[openai-gen] {r.status_code} {r.text[:300]}\n")
        r.raise_for_status()
    return _decode_image_response(r.json()["data"][0])


def call_gpt_image_with_ref(prompt: str, ref_path: Path, api_key: str, model: str, size: str) -> bytes:
    """/v1/images/edits 엔드포인트로 reference 이미지를 함께 보내 변형 생성.
    마스크 없이 전체 이미지를 prompt 방향으로 재해석 — 캐릭터 일관성 향상에 사용."""
    # multipart는 매 retry마다 파일을 다시 열어야 함
    def _send():
        with open(ref_path, "rb") as f:
            files = {"image": (ref_path.name, f, "image/png")}
            data = {"model": model, "prompt": prompt, "n": "1", "size": size}
            return requests.post(
                "https://api.openai.com/v1/images/edits",
                headers={"Authorization": f"Bearer {api_key}"},
                files=files,
                data=data,
                timeout=180,
            )

    last_resp = None
    for attempt in range(1, 5):
        try:
            r = _send()
            if r.status_code not in _RETRY_STATUSES:
                last_resp = r
                break
            last_resp = r
            sys.stderr.write(f"[retry {attempt}/4] images/edits → HTTP {r.status_code}\n")
        except requests.RequestException as e:
            sys.stderr.write(f"[retry {attempt}/4] images/edits → {type(e).__name__}: {e}\n")
        if attempt < 4:
            time.sleep(min(60, 4 * (2 ** (attempt - 1))))
    if last_resp is None:
        raise RuntimeError("images/edits: 모든 재시도 실패")
    if last_resp.status_code != 200:
        sys.stderr.write(f"[openai-edits] {last_resp.status_code} {last_resp.text[:300]}\n")
        last_resp.raise_for_status()
    return _decode_image_response(last_resp.json()["data"][0])


def download(url: str) -> bytes:
    return requests.get(url, timeout=30).content


def main() -> int:
    p = argparse.ArgumentParser(description="gpt-image-2 컷별 이미지 생성")
    p.add_argument("project_dir")
    p.add_argument("--cut", type=int, help="특정 컷만 생성 (샘플)")
    p.add_argument(
        "--substitute",
        default="",
        help="블로그 본문 이미지로 대체할 컷 번호들 (쉼표). 예: 3,6,9",
    )
    p.add_argument("--blog-images", help="블로그 본문 이미지 URL 목록 JSON 경로 (extracted.json 또는 list)")
    p.add_argument("--skip-existing", action="store_true", help="public/images/cut_NN.png가 이미 있으면 재생성하지 않음")
    p.add_argument(
        "--reference-cut",
        type=int,
        help="해당 컷의 PNG를 reference로 사용해 다른 컷을 /v1/images/edits로 생성 (캐릭터 일관성 강화)",
    )
    args = p.parse_args()

    env = load_env()
    project = Path(args.project_dir).resolve()
    captions_path = project / "captions.json"
    if not captions_path.exists():
        sys.stderr.write(
            f"[error] {captions_path} 없음. tts_elevenlabs.py + recompute_timing.py를 먼저 실행하세요.\n"
        )
        return 5

    captions = json.loads(captions_path.read_text(encoding="utf-8"))["captions"]
    targets = [c for c in captions if (args.cut is None or c["index"] == args.cut)]

    sub_indices = {int(x) for x in args.substitute.split(",") if x.strip()}
    blog_imgs: list[str] = []
    if sub_indices and args.blog_images:
        bdata = json.loads(Path(args.blog_images).read_text(encoding="utf-8"))
        blog_imgs = bdata["body_images"] if isinstance(bdata, dict) else bdata

    img_dir = project / "public" / "images"
    img_dir.mkdir(parents=True, exist_ok=True)

    ref_path: Path | None = None
    if args.reference_cut is not None:
        ref_path = img_dir / f"cut_{args.reference_cut:02d}.png"
        if not ref_path.exists():
            sys.stderr.write(
                f"[error] reference cut #{args.reference_cut} 없음. "
                f"먼저 `--cut {args.reference_cut}`로 생성하세요.\n"
            )
            return 7

    generated: list[str] = []
    for c in targets:
        out = img_dir / f"cut_{c['index']:02d}.png"
        if args.skip_existing and out.exists():
            sys.stderr.write(f"[skip] #{c['index']} (이미 존재)\n")
            generated.append(str(out))
            continue
        if c["index"] in sub_indices and blog_imgs:
            url = blog_imgs[(c["index"] - 1) % len(blog_imgs)]
            sys.stderr.write(f"[sub] #{c['index']} ← blog image {url[:80]}\n")
            out.write_bytes(download(url))
        elif ref_path is not None and c["index"] != args.reference_cut:
            prompt = build_prompt(c)
            sys.stderr.write(f"[ref-gen] #{c['index']} ({c['speaker']}) ref={ref_path.name}\n")
            out.write_bytes(call_gpt_image_with_ref(prompt, ref_path, env["OPENAI_API_KEY"], env["OPENAI_IMAGE_MODEL"], env["OPENAI_IMAGE_SIZE"]))
        else:
            prompt = build_prompt(c)
            sys.stderr.write(f"[gen] #{c['index']} ({c['speaker']}) prompt[:80]={prompt[:80]}…\n")
            out.write_bytes(call_gpt_image(prompt, env["OPENAI_API_KEY"], env["OPENAI_IMAGE_MODEL"], env["OPENAI_IMAGE_SIZE"]))
        generated.append(str(out))

    print(json.dumps({"generated": generated, "count": len(generated)}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
