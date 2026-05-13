#!/usr/bin/env python3
"""블로그 URL → {title, body, body_images} JSON 추출.

지원 플랫폼: 티스토리, 네이버 블로그, 벨로그, 브런치. 그 외 도메인은 generic 폴백.

사용 예:
    python3 extract_blog.py "https://example.tistory.com/123"
    python3 extract_blog.py --debug "https://blog.naver.com/<id>/<postNo>"
    python3 extract_blog.py --naver-postview "https://blog.naver.com/PostView.naver?..."
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Tuple, List
from urllib.parse import urljoin, urlparse

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError as e:
    sys.stderr.write(
        "[error] 의존성 누락: " + str(e) + "\n"
        "다음 명령으로 설치하세요:\n"
        "  pip install requests beautifulsoup4\n"
    )
    sys.exit(2)


USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)
HEADERS = {"User-Agent": USER_AGENT, "Accept-Language": "ko,en;q=0.9"}

PLATFORM_SELECTORS = {
    "tistory": [
        "article.entry-content",
        ".tt_article_useless_p_margin",
        ".article_view",
        ".entry-content",
        "div.article",
        "#article-view",
    ],
    "naver": [
        "div.se-main-container",
        "#postViewArea",
        ".post-view",
        ".se_component_wrap",
    ],
    "velog": [
        "div.atom-one",
        "div.sc-1cbssjk-1",
        "div.sc-fbIWvr",
    ],
    "brunch": [
        "div.wrap_body",
        ".article_view",
        ".wrap_view_article",
    ],
}


def detect_platform(url: str) -> str:
    host = urlparse(url).netloc.lower()
    if "tistory.com" in host:
        return "tistory"
    if "naver.com" in host and "blog" in host:
        return "naver"
    if "velog.io" in host:
        return "velog"
    if "brunch.co.kr" in host:
        return "brunch"
    return "generic"


def fetch(url: str) -> str:
    r = requests.get(url, headers=HEADERS, timeout=15)
    r.raise_for_status()
    if not r.encoding or r.encoding.lower() == "iso-8859-1":
        r.encoding = r.apparent_encoding or "utf-8"
    return r.text


def fetch_naver(url: str) -> str:
    """blog.naver.com 본문은 iframe#mainFrame 안에 있어 한 번 더 페치한다."""
    if "m.blog.naver.com" in url or "PostView.naver" in url:
        return fetch(url)
    outer = fetch(url)
    soup = BeautifulSoup(outer, "html.parser")
    iframe = soup.select_one("iframe#mainFrame")
    if iframe is None or not iframe.get("src"):
        return outer
    return fetch(urljoin("https://blog.naver.com", iframe["src"]))


def get_title(soup: BeautifulSoup) -> str:
    og = soup.select_one("meta[property='og:title']")
    if og and og.get("content"):
        return og["content"].strip()
    t = soup.select_one("title")
    return t.get_text(strip=True) if t else ""


def get_body(soup: BeautifulSoup, platform: str) -> Tuple[str, List[str]]:
    container = None
    for sel in PLATFORM_SELECTORS.get(platform, []):
        container = soup.select_one(sel)
        if container is not None:
            break
    if container is None:
        container = soup.select_one("article") or soup.select_one("main") or soup.body
    if container is None:
        return "", []

    for tag in container.select("script, style, nav, header, footer"):
        tag.decompose()

    text = container.get_text("\n", strip=True)
    text = re.sub(r"\n{3,}", "\n\n", text)

    images: List[str] = []
    for img in container.select("img"):
        src = img.get("src") or img.get("data-src") or img.get("data-lazy-src")
        if not src:
            continue
        if src.startswith("//"):
            src = "https:" + src
        if src.startswith(("http://", "https://")):
            if src not in images:
                images.append(src)
    return text, images


def main() -> int:
    p = argparse.ArgumentParser(description="블로그 URL → JSON 본문/이미지 추출")
    p.add_argument("url", help="블로그 글 URL")
    p.add_argument("--debug", action="store_true", help="HTML 길이 등을 stderr에 출력")
    p.add_argument(
        "--naver-postview",
        action="store_true",
        help="입력 URL을 네이버 PostView 본문 URL로 간주 (iframe 우회)",
    )
    args = p.parse_args()

    platform = detect_platform(args.url)
    html = fetch(args.url) if (platform != "naver" or args.naver_postview) else fetch_naver(args.url)

    soup = BeautifulSoup(html, "html.parser")
    title = get_title(soup)
    body, images = get_body(soup, platform)

    if args.debug:
        sys.stderr.write(
            f"[debug] platform={platform} html_len={len(html)} "
            f"body_len={len(body)} img_count={len(images)}\n"
        )

    result = {
        "platform": platform,
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
