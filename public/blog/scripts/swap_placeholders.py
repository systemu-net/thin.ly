#!/usr/bin/env python3
"""
Replace placeholder.svg references in each blog post with the per-image
local paths + descriptive alt text.

Pattern in each post:
  - frontmatter:  image: /assets/images/placeholder.svg
                  image_alt: Decorative placeholder image
  - body, 3 times:
        <img src="/assets/images/placeholder.svg"
             alt="Decorative placeholder image"
             loading="lazy">

This script walks each post and replaces the 4 occurrences in order using
the mapping below. It does NOT touch the existing figcaption text.

Re-runs are idempotent: once a post no longer has placeholder.svg, this
script makes no changes.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# (filename, [(rel_path, alt), ...] in order: hero, inline1, inline2, inline3)
POSTS: list[tuple[str, list[tuple[str, str]]]] = [
    (
        "2026-05-25-utm-parameters-with-shortened-links.md",
        [
            ("/assets/images/utm-parameters/hero.jpg",
             "Analytics dashboard showing campaign attribution data"),
            ("/assets/images/utm-parameters/utm-stack.jpg",
             "Diagram of UTM parameters layered on a destination URL"),
            ("/assets/images/utm-parameters/vocabulary.jpg",
             "Marketer reviewing a UTM vocabulary list on a whiteboard"),
            ("/assets/images/utm-parameters/workflow.jpg",
             "Workflow diagram from campaign brief through tagged short link to analytics report"),
        ],
    ),
    (
        "2026-05-18-qr-codes-for-print-marketing.md",
        [
            ("/assets/images/qr-codes-for-print/hero.jpg",
             "QR code printed on a poster being scanned by a smartphone"),
            ("/assets/images/qr-codes-for-print/dynamic-vs-static.jpg",
             "Dynamic versus static QR code comparison"),
            ("/assets/images/qr-codes-for-print/sizing.jpg",
             "Large QR code on a hotel-lobby poster"),
            ("/assets/images/qr-codes-for-print/context.jpg",
             "QR code printed beside a clear product photo with explanatory text"),
        ],
    ),
    (
        "2026-05-11-understanding-link-analytics.md",
        [
            ("/assets/images/link-analytics/hero.jpg",
             "Analytics dashboard with click charts and geographic distribution"),
            ("/assets/images/link-analytics/uniques.jpg",
             "Chart comparing total clicks to unique clicks over time"),
            ("/assets/images/link-analytics/geo.jpg",
             "World map heatmap of click density by country"),
            ("/assets/images/link-analytics/hourly.jpg",
             "24-hour histogram showing click distribution by hour of day"),
        ],
    ),
    (
        "2026-05-04-url-shortener-security.md",
        [
            ("/assets/images/url-shortener-security/hero.jpg",
             "Padlock icon on a network of glowing connections representing link security"),
            ("/assets/images/url-shortener-security/threats.jpg",
             "Diagram showing four categories of malicious link use"),
            ("/assets/images/url-shortener-security/scanning.jpg",
             "Server inspecting a URL through multiple scanning layers"),
            ("/assets/images/url-shortener-security/interstitial.jpg",
             "Browser showing a safety interstitial page warning about a blocked link"),
        ],
    ),
    (
        "2026-04-27-branded-vs-generic-shorteners.md",
        [
            ("/assets/images/branded-vs-generic/hero.jpg",
             "Branded short URL displayed prominently on a billboard"),
            ("/assets/images/branded-vs-generic/trust.jpg",
             "Phone showing two link previews — one branded, one generic"),
            ("/assets/images/branded-vs-generic/cost.jpg",
             "Cost breakdown chart for branded custom-domain setup"),
            ("/assets/images/branded-vs-generic/subdomain.jpg",
             "Subdomain configuration interface for a branded short-link service"),
        ],
    ),
    (
        "2026-04-20-link-governance-for-marketing-teams.md",
        [
            ("/assets/images/link-governance/hero.jpg",
             "Audit-log style interface showing link state changes over time"),
            ("/assets/images/link-governance/pause.jpg",
             "Dashboard showing a paused short link with the unpause action highlighted"),
            ("/assets/images/link-governance/routing.jpg",
             "Routing rules splitting traffic by geography and device type"),
            ("/assets/images/link-governance/audit.jpg",
             "Timeline view of an audit log with each state change tagged by actor"),
        ],
    ),
    (
        "2026-04-13-custom-domains-for-short-links.md",
        [
            ("/assets/images/custom-domains/hero.jpg",
             "DNS configuration panel showing CNAME records being edited"),
            ("/assets/images/custom-domains/picking.jpg",
             "Selection of candidate short-domain options across multiple TLDs"),
            ("/assets/images/custom-domains/dns.jpg",
             "DNS zone editor showing CNAME and A record entries for a short domain"),
            ("/assets/images/custom-domains/ssl.jpg",
             "Browser address bar showing a valid HTTPS certificate on a branded short link"),
        ],
    ),
    (
        "2026-04-06-qr-code-vs-short-link.md",
        [
            ("/assets/images/qr-vs-link/hero.jpg",
             "A poster showing a QR code and a printed short URL side by side"),
            ("/assets/images/qr-vs-link/surfaces.jpg",
             "Grid of surfaces with optimal wrapper labeled — podcast, poster, social, email"),
            ("/assets/images/qr-vs-link/fallback.jpg",
             "Printed material showing a QR code with the short URL printed beneath it as fallback"),
            ("/assets/images/qr-vs-link/decision.jpg",
             "Decision flowchart from surface type to recommended link wrapper"),
        ],
    ),
]

PLACEHOLDER = "/assets/images/placeholder.svg"
PLACEHOLDER_ALT = "Decorative placeholder image"

# Frontmatter pattern: matches both the image: line and image_alt: line as a pair
FRONTMATTER_RE = re.compile(
    r"^image: " + re.escape(PLACEHOLDER) + r"\n"
    r"image_alt: " + re.escape(PLACEHOLDER_ALT) + r"\n",
    flags=re.MULTILINE,
)

# Body pattern: <img src="..."  alt="..."  loading="lazy">
# Tolerant of attribute order and whitespace.
BODY_RE = re.compile(
    r'<img\s+src="' + re.escape(PLACEHOLDER) + r'"\s+'
    r'alt="' + re.escape(PLACEHOLDER_ALT) + r'"\s+'
    r'loading="lazy">'
)


def swap_in_post(path: Path, replacements: list[tuple[str, str]]) -> int:
    """Apply the 4 replacements to a single post. Returns count of swaps."""
    text = path.read_text(encoding="utf-8")
    original = text
    count = 0

    # 1) Frontmatter (hero) — exactly one occurrence
    hero_path, hero_alt = replacements[0]
    text, n = FRONTMATTER_RE.subn(
        f"image: {hero_path}\nimage_alt: {hero_alt}\n",
        text,
        count=1,
    )
    count += n

    # 2) Body figures — 3 in order
    for body_path, body_alt in replacements[1:]:
        new_img = (
            f'<img src="{body_path}" '
            f'alt="{body_alt}" '
            f'loading="lazy">'
        )
        text, n = BODY_RE.subn(new_img, text, count=1)
        count += n

    if text != original:
        path.write_text(text, encoding="utf-8")

    return count


def main() -> int:
    posts_dir = Path(__file__).resolve().parent.parent / "_posts"
    print(f"Working from {posts_dir}/")
    total = 0
    for filename, replacements in POSTS:
        target = posts_dir / filename
        if not target.exists():
            print(f"  MISSING {filename}")
            continue
        swaps = swap_in_post(target, replacements)
        total += swaps
        status = "ok" if swaps == 4 else f"{swaps}/4 only — already-swapped?"
        print(f"  {status:30s} {filename}")
    print()
    print(f"Done: {total} replacements across {len(POSTS)} posts (expected 32).")
    return 0 if total == 32 else 1


if __name__ == "__main__":
    sys.exit(main())
