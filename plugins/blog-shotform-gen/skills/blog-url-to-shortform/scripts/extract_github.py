#!/usr/bin/env python3
"""GitHub repo URL → {title, body, body_images} JSON 추출.

사용 예:
    python3 extract_github.py "https://github.com/anthropics/claude-code"
    python3 extract_github.py --debug "https://github.com/owner/repo/tree/dev"

전략:
  1) URL → owner/repo 파싱 (subpath/.git/쿼리 제거)
  2) raw.githubusercontent.com 에서 README 후보를 main / master 브랜치 × 파일명 후보로 순차 fetch
  3) 모두 실패하면 api.github.com/repos/<owner>/<repo> 의 default_branch 로 재시도
  4) 마크다운 그대로 body 로 반환 (draft_captions 가 처리). HTML 태그 제거.
     이미지는 ![](url) 과 <img src> 양쪽에서 절대 URL 만 추출.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from typing import List, Optional, Tuple
from urllib.parse import urlparse

try:
    import requests
except ImportError as e:
    sys.stderr.write(
        "[error] 의존성 누락: " + str(e) + "\n"
        "다음 명령으로 설치하세요:\n"
        "  pip install requests\n"
    )
    sys.exit(2)


USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)
HEADERS = {"User-Agent": USER_AGENT, "Accept": "text/plain, */*"}

# 후보가 많아 보이지만 모두 raw 단순 GET — 평균 1~2회 안에 해결.
README_FILENAMES = ["README.md", "readme.md", "Readme.md", "README.MD", "README"]
DEFAULT_BRANCHES = ["main", "master"]


def parse_owner_repo(url: str) -> Tuple[str, str]:
    u = urlparse(url)
    if u.netloc.lower() not in ("github.com", "www.github.com"):
        raise ValueError(f"github.com URL 아님: {url}")
    parts = [p for p in u.path.split("/") if p]
    if len(parts) < 2:
        raise ValueError(f"owner/repo 형식 아님: {url}")
    owner, repo = parts[0], parts[1]
    if repo.endswith(".git"):
        repo = repo[:-4]
    return owner, repo


def fetch_text(url: str, timeout: int = 12) -> Optional[str]:
    try:
        r = requests.get(url, headers=HEADERS, timeout=timeout)
    except requests.RequestException:
        return None
    if r.status_code != 200:
        return None
    if not r.encoding or r.encoding.lower() == "iso-8859-1":
        r.encoding = r.apparent_encoding or "utf-8"
    return r.text


def fetch_default_branch(owner: str, repo: str) -> Optional[str]:
    api = f"https://api.github.com/repos/{owner}/{repo}"
    try:
        r = requests.get(api, headers={**HEADERS, "Accept": "application/vnd.github+json"}, timeout=12)
    except requests.RequestException:
        return None
    if r.status_code != 200:
        return None
    try:
        return r.json().get("default_branch")
    except ValueError:
        return None


def fetch_readme(owner: str, repo: str, debug: bool = False) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """반환: (markdown, branch, filename). 실패 시 모두 None."""
    for branch in DEFAULT_BRANCHES:
        for fname in README_FILENAMES:
            url = f"https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{fname}"
            txt = fetch_text(url)
            if debug:
                sys.stderr.write(f"[debug] try {url} → {'HIT' if txt else 'miss'}\n")
            if txt:
                return txt, branch, fname

    # main/master 둘 다 miss → API 로 default branch 알아서 재시도
    branch = fetch_default_branch(owner, repo)
    if not branch or branch in DEFAULT_BRANCHES:
        return None, None, None
    for fname in README_FILENAMES:
        url = f"https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{fname}"
        txt = fetch_text(url)
        if debug:
            sys.stderr.write(f"[debug] try {url} (api branch) → {'HIT' if txt else 'miss'}\n")
        if txt:
            return txt, branch, fname
    return None, None, None


# ![alt](url) 또는 ![alt](url "title")
MD_IMAGE_RE = re.compile(r"!\[[^\]]*\]\(\s*(\S+?)(?:\s+\"[^\"]*\")?\s*\)")
# <img src="url">  (single or double quote)
HTML_IMAGE_RE = re.compile(r"<img\b[^>]*\bsrc\s*=\s*[\"']([^\"']+)[\"']", re.IGNORECASE)
# 모든 html tag (script/style 포함 후처리)
HTML_TAG_RE = re.compile(r"<[^>]+>")
# 마크다운 링크 [text](url) → text 만 남김
MD_LINK_RE = re.compile(r"\[([^\]]+)\]\([^)]+\)")
# 마크다운 이미지 → 통째로 제거 (이미지는 따로 추출됨)
MD_IMAGE_STRIP_RE = re.compile(r"!\[[^\]]*\]\([^)]*\)")
# 배지 같은 img 태그도 본문에선 제거
HTML_IMG_STRIP_RE = re.compile(r"<img\b[^>]*/?>", re.IGNORECASE)


def normalize_image_url(src: str, owner: str, repo: str, branch: str) -> Optional[str]:
    src = src.strip()
    if not src:
        return None
    if src.startswith("//"):
        return "https:" + src
    if src.startswith(("http://", "https://")):
        return src
    # 상대경로 → raw URL 절대화
    if src.startswith("/"):
        path = src.lstrip("/")
    else:
        path = src
    return f"https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}"


def extract_images(md: str, owner: str, repo: str, branch: str) -> List[str]:
    out: List[str] = []
    for src in MD_IMAGE_RE.findall(md) + HTML_IMAGE_RE.findall(md):
        url = normalize_image_url(src, owner, repo, branch)
        if not url:
            continue
        if url in out:
            continue
        # 배지/아이콘 (shields/badge/svg) 는 본문 시각 자산이 아님 → 스킵
        low = url.lower()
        if any(k in low for k in ("shields.io", "badge", ".svg")):
            continue
        out.append(url)
    return out


def markdown_to_text(md: str) -> str:
    """본문용 정리. 코드블록은 보존 (draft 가 인지하도록), 링크/이미지/HTML 태그만 정리."""
    # ![](url) 통째 제거 — 본문에는 alt 만 있어도 의미가 흐려짐
    md = MD_IMAGE_STRIP_RE.sub("", md)
    # <img ...> 제거
    md = HTML_IMG_STRIP_RE.sub("", md)
    # [text](url) → text
    md = MD_LINK_RE.sub(r"\1", md)
    # 나머지 HTML 태그 제거
    md = HTML_TAG_RE.sub("", md)
    # 연속 빈 줄 정리
    md = re.sub(r"\n{3,}", "\n\n", md)
    return md.strip()


def extract_title(md: str, fallback: str) -> str:
    for line in md.splitlines():
        s = line.strip()
        if s.startswith("# "):
            return s[2:].strip()
    return fallback


def main() -> int:
    p = argparse.ArgumentParser(description="GitHub repo README → JSON 본문/이미지 추출")
    p.add_argument("url", help="https://github.com/owner/repo")
    p.add_argument("--debug", action="store_true", help="fetch 시도/길이를 stderr 에 출력")
    args = p.parse_args()

    try:
        owner, repo = parse_owner_repo(args.url)
    except ValueError as e:
        sys.stderr.write(f"[error] {e}\n")
        return 2

    md, branch, fname = fetch_readme(owner, repo, debug=args.debug)
    if md is None:
        sys.stderr.write(
            f"[error] README 를 찾지 못했습니다 ({owner}/{repo}). public 저장소인지, README.md 가 있는지 확인하세요.\n"
        )
        return 3

    assert branch is not None  # mypy hint
    title = extract_title(md, fallback=f"{owner}/{repo}")
    body = markdown_to_text(md)
    images = extract_images(md, owner, repo, branch)

    if args.debug:
        sys.stderr.write(
            f"[debug] owner={owner} repo={repo} branch={branch} file={fname} "
            f"md_len={len(md)} body_len={len(body)} img_count={len(images)}\n"
        )

    result = {
        "platform": "github",
        "url": args.url,
        "title": title,
        "body": body,
        "body_images": images,
        "char_count": len(body),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
