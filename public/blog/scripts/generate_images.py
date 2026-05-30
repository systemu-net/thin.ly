#!/usr/bin/env python3
"""
Generate the 32 blog post images via Pollinations.ai.

Pollinations is a free no-key AI-image endpoint. Each request takes a
prompt as part of the URL path and returns a generated JPEG. We download
all 32 images sequentially with a small concurrency, dedupe-safe (skips
files that already exist), and save them at the paths referenced by the
post markdown.

Usage:
    python3 blog/scripts/generate_images.py

Re-runs are safe: existing files are skipped. Delete a file to regenerate it.
"""

from __future__ import annotations

import os
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# ------------------------------------------------------------------
# Style guide — prefix on every prompt to keep the 32 images visually
# coherent. Comes from blog/IMAGES.md.
# ------------------------------------------------------------------
STYLE_PREFIX = (
    "Editorial illustration in a clean, modern, slightly muted style. "
    "Soft natural lighting. Generous negative space. Brand accent color "
    "is violet (#6d28d9, #7c3aed). Avoid cliched stock-photography tropes "
    "- no high-fives, no people pointing at laptops, no blueprint hands. "
    "Avoid heavy text overlays; if any text is shown in the image, keep "
    "it short and legible. 16:9 aspect ratio, photorealistic or 3D render "
    "quality, not flat vector art. "
)

# ------------------------------------------------------------------
# The 32 images. (target_path, prompt)
# Target paths are relative to blog/assets/images/.
# Hero images: 1600x900. Inline images: 1200x675.
# Pollinations seems to cap at 1024x576 but we request the full size.
# ------------------------------------------------------------------
IMAGES = [
    # Post 1 - UTM Parameters
    (
        "utm-parameters/hero.jpg",
        1600, 900,
        "An editorial overhead shot of a desktop workspace with a large "
        "laptop screen showing a colorful analytics dashboard. Multiple "
        "campaign cards visible with click counts and percentage changes. "
        "Coffee cup, notebook, and a smartphone with a similar dashboard "
        "view nearby. Muted natural light from a window on the left. "
        "Violet accents in the dashboard visuals.",
    ),
    (
        "utm-parameters/utm-stack.jpg",
        1200, 675,
        "A clean 3D-rendered diagram showing layered translucent cards: "
        "top card labeled 'Short link wrapper' with a thin.ly-style URL, "
        "second card 'Destination URL' with a longer path, third card "
        "'UTM parameters' with key/value chips. The cards are stacked "
        "with visible depth, soft purple gradient background.",
    ),
    (
        "utm-parameters/vocabulary.jpg",
        1200, 675,
        "Close-up of a whiteboard or notebook page with a hand-written "
        "marketing UTM convention list. Pen resting on the notebook. "
        "Soft daylight from one side. Subtle violet highlighter marks "
        "on key terms.",
    ),
    (
        "utm-parameters/workflow.jpg",
        1200, 675,
        "A clean, modern process diagram with four numbered steps "
        "connected by arrows: 1) Campaign brief, 2) Tagged destination "
        "URL, 3) Shortened link, 4) Attributed click in analytics. Each "
        "step shown as an icon-and-label card. Violet accent color on "
        "the arrows. Light grey background. Minimalist.",
    ),

    # Post 2 - QR Codes for Print
    (
        "qr-codes-for-print/hero.jpg",
        1600, 900,
        "Photorealistic close-up of a printed event poster on a wall, "
        "with a large QR code prominently in the lower right and a short "
        "URL printed clearly underneath. A hand is holding a smartphone "
        "framing the QR code, mid-scan. Warm gallery lighting. Shallow "
        "depth of field with the QR code in sharp focus.",
    ),
    (
        "qr-codes-for-print/dynamic-vs-static.jpg",
        1200, 675,
        "Side-by-side comparison illustration: left half labeled STATIC "
        "showing a printed QR code with a broken or error icon on the "
        "destination screen; right half labeled DYNAMIC showing the same "
        "printed QR code but the destination screen has been updated to "
        "a new campaign. Subtle violet accent labels. Clean editorial "
        "design.",
    ),
    (
        "qr-codes-for-print/sizing.jpg",
        1200, 675,
        "A hotel lobby with a large vertical advertising poster on a "
        "stand, a large QR code prominently displayed at viewing height, "
        "a person standing across the room about three meters away "
        "holding up their phone to scan. The scale relationship between "
        "viewer distance and QR code size is clear.",
    ),
    (
        "qr-codes-for-print/context.jpg",
        1200, 675,
        "A printed restaurant table card or menu showing a QR code with "
        "clear friendly text above it (scan to see the wine list). Warm "
        "restaurant lighting, slight depth of field, the card framed by "
        "a partial place setting. Editorial food-magazine style.",
    ),

    # Post 3 - Link Analytics
    (
        "link-analytics/hero.jpg",
        1600, 900,
        "A wide editorial shot of a modern analytics dashboard on a "
        "large monitor: a line chart of clicks over time, a small world "
        "map with country click densities, a device-split donut chart, "
        "and a referrer table. Violet brand accent on key metrics. "
        "Slightly off-axis composition with a coffee mug and notebook in "
        "the foreground, suggesting a marketer reviewing data.",
    ),
    (
        "link-analytics/uniques.jpg",
        1200, 675,
        "A side-by-side comparison of two line charts on a clean "
        "dashboard interface: one labeled 'Total clicks' (higher line), "
        "one labeled 'Unique clicks' (lower line, parallel). The gap "
        "between them is shaded subtly. Violet accent on the unique "
        "line. Minimalist, editorial.",
    ),
    (
        "link-analytics/geo.jpg",
        1200, 675,
        "A world map shown as a clean choropleth heatmap with click "
        "densities indicated by color intensity (light cream to deep "
        "violet). Sparse country labels for the highest-density regions. "
        "Subtle grid background. Dashboard-card style framing.",
    ),
    (
        "link-analytics/hourly.jpg",
        1200, 675,
        "A 24-hour bar histogram showing click distribution by hour of "
        "day, with a clear working-hours peak (9am-6pm) and a small "
        "late-evening secondary peak. Violet bars on a soft grey "
        "background. Hour labels on x-axis, 'Clicks' label on y-axis. "
        "Clean dashboard chart aesthetic.",
    ),

    # Post 4 - URL Shortener Security
    (
        "url-shortener-security/hero.jpg",
        1600, 900,
        "A photorealistic abstract concept of digital trust: a glowing "
        "padlock icon floating above a network of soft-glowing connection "
        "lines representing URL redirects. Deep dark navy background "
        "with violet and cyan accent glows. Cinematic lighting. Modern "
        "3D-art style, not clipart.",
    ),
    (
        "url-shortener-security/threats.jpg",
        1200, 675,
        "A clean grid of four threat-icon cards labeled: Malware, "
        "Phishing, Scams, Policy violations. Each card has a minimalist "
        "warning icon and a soft red or orange accent. Editorial diagram "
        "style on a light background.",
    ),
    (
        "url-shortener-security/scanning.jpg",
        1200, 675,
        "An abstract diagram showing a URL passing through several "
        "layered scanner panels — labeled with names like Safe Browsing, "
        "Heuristic check, Sandboxed inspection. Each panel adds a check "
        "mark or annotation as the URL passes through. Modern "
        "glassmorphism style with violet gradient accents.",
    ),
    (
        "url-shortener-security/interstitial.jpg",
        1200, 675,
        "A laptop screen displaying a clean, friendly safety warning "
        "page: a shield icon, headline 'This link was flagged as "
        "unsafe', explanatory body text, and a 'Report a false positive' "
        "button. The browser address bar shows a thin.ly short URL. "
        "Soft natural lighting. Photographed from a slight angle.",
    ),

    # Post 5 - Branded vs Generic
    (
        "branded-vs-generic/hero.jpg",
        1600, 900,
        "A large outdoor billboard in a city at golden hour, displaying "
        "a campaign with a branded short URL (e.g. 'acme.link/launch') "
        "prominently centered. The billboard's brand identity is clear. "
        "Wide cinematic shot looking up at the billboard. Warm light, "
        "deep shadows. Photorealistic.",
    ),
    (
        "branded-vs-generic/trust.jpg",
        1200, 675,
        "A smartphone screen split-screen showing two link previews "
        "side by side: left one shows a generic-shortener URL, right "
        "one shows a branded URL. A subtle 'more trusted' annotation on "
        "the branded side. Clean modern UI. Editorial product-photography "
        "style.",
    ),
    (
        "branded-vs-generic/cost.jpg",
        1200, 675,
        "A clean horizontal bar-chart illustration showing cost "
        "categories for branded domain setup: 'Domain registration', "
        "'Plan tier', 'DNS/SSL', 'Internal coordination'. Bars in "
        "graduated violet shades. Soft grey background. Dashboard-style.",
    ),
    (
        "branded-vs-generic/subdomain.jpg",
        1200, 675,
        "A clean UI mockup of a 'Custom domain' configuration panel "
        "inside a modern SaaS product: input field showing a subdomain, "
        "a status badge 'Verified, SSL active', and a 'Save' button in "
        "violet. Soft drop shadows. Light theme.",
    ),

    # Post 6 - Link Governance
    (
        "link-governance/hero.jpg",
        1600, 900,
        "A wide editorial shot of a modern audit-log interface on a "
        "monitor: timeline view with state-change entries (paused, "
        "resumed, destination changed, expired), each entry tagged with "
        "a user avatar and timestamp. Violet accent on the most recent "
        "entry. Slightly off-axis composition with a desk plant and "
        "coffee mug in the soft foreground.",
    ),
    (
        "link-governance/pause.jpg",
        1200, 675,
        "A close-up UI mockup of a link's dashboard row with a clearly "
        "visible 'Paused' status badge in soft amber and a 'Resume' "
        "button highlighted in violet. The click-count number is "
        "preserved next to the status. Modern, clean SaaS aesthetic.",
    ),
    (
        "link-governance/routing.jpg",
        1200, 675,
        "A flow diagram showing a single short link branching into "
        "three destinations based on conditions: if country = EU, if "
        "device = mobile, default. Clean diagram with violet condition "
        "branches. Light theme.",
    ),
    (
        "link-governance/audit.jpg",
        1200, 675,
        "A vertical timeline UI showing successive link events: Created, "
        "Destination updated, Paused, Resumed - each with a small avatar "
        "and timestamp. Clean modern interface on a light background.",
    ),

    # Post 7 - Custom Domains
    (
        "custom-domains/hero.jpg",
        1600, 900,
        "A close-up of a DNS zone editor on a developer's monitor: rows "
        "of records (A, CNAME, TXT) with editable fields. One CNAME "
        "record is highlighted in violet, mid-edit. Slight bokeh in the "
        "background suggesting a development environment. Modern editor "
        "aesthetic.",
    ),
    (
        "custom-domains/picking.jpg",
        1200, 675,
        "A clean grid of candidate short-domain options across multiple "
        "TLDs: 'acme.link', 'acme.co', 'acme.io', 'go.acme.com', each "
        "with a small 'available' or 'taken' indicator. Modern "
        "domain-search UI mockup. Violet accents on available results.",
    ),
    (
        "custom-domains/dns.jpg",
        1200, 675,
        "A clean table-style UI showing DNS records for a short domain: "
        "CNAME record pointing to a target, two A records, a TXT "
        "verification record. Each row has a small status indicator. "
        "Modern admin-panel aesthetic on a light background. Violet "
        "accents.",
    ),
    (
        "custom-domains/ssl.jpg",
        1200, 675,
        "A close-up of a browser's address bar showing an HTTPS URL "
        "with a green padlock icon and a valid certificate tooltip "
        "showing 'Connection is secure, Issued by Let's Encrypt'. Clean "
        "modern browser UI. Soft natural lighting on the laptop screen.",
    ),

    # Post 8 - QR vs Short Link
    (
        "qr-vs-link/hero.jpg",
        1600, 900,
        "Photorealistic close-up of a printed marketing card or poster "
        "showing a QR code in the upper half and a printed short URL "
        "prominently in the lower half. The two options are visually "
        "balanced. Warm natural lighting, slight depth of field, "
        "editorial product-photo style.",
    ),
    (
        "qr-vs-link/surfaces.jpg",
        1200, 675,
        "A clean 2x3 grid of surface icons labeled: Podcast, Poster, "
        "Social post, Email, Conference badge, Product packaging, each "
        "with a small badge indicating 'Short link' or 'QR code' or "
        "'Both'. Modern editorial diagram style with violet accents.",
    ),
    (
        "qr-vs-link/fallback.jpg",
        1200, 675,
        "A close-up of a printed promotional card with a QR code "
        "centered and a clearly readable short URL printed in slightly "
        "smaller type directly beneath it. The fallback URL is visually "
        "intentional, not an afterthought. Warm print-design aesthetic, "
        "slight paper texture.",
    ),
    (
        "qr-vs-link/decision.jpg",
        1200, 675,
        "A clean horizontal decision flowchart: start node asking 'Can "
        "the user type this URL in 5 seconds without a mistake?' "
        "branching to two outcomes: YES leading to 'Short link' and NO "
        "leading to 'QR code plus short URL fallback'. Modern violet-"
        "accented diagram on a light background. Editorial style.",
    ),
]


def build_url(prompt: str, width: int, height: int, seed: int) -> str:
    """Build a Pollinations.ai image URL from a prompt and dimensions."""
    full_prompt = STYLE_PREFIX + prompt
    encoded = urllib.parse.quote(full_prompt, safe="")
    return (
        f"https://image.pollinations.ai/prompt/{encoded}"
        f"?width={width}&height={height}&seed={seed}&model=flux&nologo=true"
    )


def fetch(target: Path, url: str, attempt: int = 1) -> tuple[Path, bool, str]:
    """Download one image. Returns (path, success, message)."""
    if target.exists() and target.stat().st_size > 1000:
        return target, True, "exists"

    target.parent.mkdir(parents=True, exist_ok=True)

    req = urllib.request.Request(
        url,
        headers={"User-Agent": "thin.ly-blog-image-gen/1.0"},
    )

    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = resp.read()
        if len(data) < 5000:
            raise RuntimeError(f"response too small: {len(data)} bytes")
        target.write_bytes(data)
        return target, True, f"{len(data) // 1024} KB"
    except Exception as exc:  # noqa: BLE001
        if attempt < 3:
            time.sleep(2 * attempt)
            return fetch(target, url, attempt + 1)
        return target, False, f"failed after 3 attempts: {exc}"


def main() -> int:
    root = Path(__file__).resolve().parent.parent / "assets" / "images"
    print(f"Generating {len(IMAGES)} images into {root}/")
    print()

    # Deterministic seed per image — same image always comes out the same
    # so reruns don't drift if you regenerate a single file.
    jobs = []
    for index, (rel_path, w, h, prompt) in enumerate(IMAGES):
        seed = 1000 + index
        url = build_url(prompt, w, h, seed)
        target = root / rel_path
        jobs.append((target, url, rel_path))

    successes, failures = [], []

    # Concurrency = 4. Higher than that and Pollinations starts rate-limiting.
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {
            pool.submit(fetch, target, url): rel
            for target, url, rel in jobs
        }
        for fut in as_completed(futures):
            rel = futures[fut]
            path, ok, msg = fut.result()
            if ok:
                successes.append(rel)
                print(f"  ok   {rel:55s} ({msg})")
            else:
                failures.append(rel)
                print(f"  FAIL {rel:55s} {msg}")

    print()
    print(f"Done: {len(successes)} ok, {len(failures)} failed.")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
