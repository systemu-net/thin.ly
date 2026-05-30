#!/usr/bin/env python3
"""
Generate 32 procedural SVG illustrations as a fallback for the AI-image
plan. Each SVG is a clean editorial composition in thin.ly's violet palette
with topic-appropriate iconography. Inline-only, no external dependencies.

Saves to: blog/assets/images/<post-slug>/<image-name>.svg
"""

from __future__ import annotations

import math
import random
import sys
from pathlib import Path

# ----- color palette -----
# Soft cream / violet brand. Subset of the variables in main.scss.
PALETTES = [
    # (bg-light, bg-dark, accent, accent-soft, fg)
    ("#faf7ff", "#ede4ff", "#6d28d9", "#a78bfa", "#1a1430"),  # violet
    ("#fef5f8", "#fbe3ee", "#9d174d", "#f472b6", "#2d1018"),  # magenta
    ("#f0f9ff", "#dbeafe", "#1e40af", "#60a5fa", "#0c1830"),  # blue
    ("#ecfdf5", "#d1fae5", "#047857", "#34d399", "#0a1f1a"),  # emerald
    ("#fffbeb", "#fef3c7", "#b45309", "#fbbf24", "#2a1810"),  # amber
    ("#f5f3ff", "#ddd6fe", "#5b21b6", "#8b5cf6", "#1a0f30"),  # indigo
    ("#fef2f2", "#fee2e2", "#991b1b", "#f87171", "#2a0a0a"),  # red
    ("#f0fdfa", "#ccfbf1", "#0f766e", "#2dd4bf", "#0a1f1d"),  # teal
]

# ----- definitions -----
# (rel_path, width, height, template_name, palette_index)
IMAGES = [
    # Post 1 — UTM (violet)
    ("utm-parameters/hero.jpg",          1600, 900, "dashboard",   0),
    ("utm-parameters/utm-stack.jpg",     1200, 675, "stack",        0),
    ("utm-parameters/vocabulary.jpg",    1200, 675, "tags",         0),
    ("utm-parameters/workflow.jpg",      1200, 675, "flow",         0),

    # Post 2 — QR Codes for Print (magenta)
    ("qr-codes-for-print/hero.jpg",         1600, 900, "qrcode",   1),
    ("qr-codes-for-print/dynamic-vs-static.jpg", 1200, 675, "split", 1),
    ("qr-codes-for-print/sizing.jpg",       1200, 675, "scale",   1),
    ("qr-codes-for-print/context.jpg",      1200, 675, "card",     1),

    # Post 3 — Link Analytics (blue)
    ("link-analytics/hero.jpg",       1600, 900, "dashboard",     2),
    ("link-analytics/uniques.jpg",    1200, 675, "twolines",      2),
    ("link-analytics/geo.jpg",        1200, 675, "map",            2),
    ("link-analytics/hourly.jpg",     1200, 675, "histogram",     2),

    # Post 4 — Security (indigo)
    ("url-shortener-security/hero.jpg",        1600, 900, "shield",  5),
    ("url-shortener-security/threats.jpg",     1200, 675, "grid4",   5),
    ("url-shortener-security/scanning.jpg",    1200, 675, "layers",  5),
    ("url-shortener-security/interstitial.jpg",1200, 675, "alert",   5),

    # Post 5 — Branded vs Generic (emerald)
    ("branded-vs-generic/hero.jpg",       1600, 900, "billboard", 3),
    ("branded-vs-generic/trust.jpg",      1200, 675, "split",     3),
    ("branded-vs-generic/cost.jpg",       1200, 675, "bars",      3),
    ("branded-vs-generic/subdomain.jpg",  1200, 675, "form",      3),

    # Post 6 — Governance (amber)
    ("link-governance/hero.jpg",     1600, 900, "timeline",  4),
    ("link-governance/pause.jpg",    1200, 675, "card",      4),
    ("link-governance/routing.jpg",  1200, 675, "flow",      4),
    ("link-governance/audit.jpg",    1200, 675, "timeline",  4),

    # Post 7 — Custom Domains (teal)
    ("custom-domains/hero.jpg",     1600, 900, "form",     7),
    ("custom-domains/picking.jpg",  1200, 675, "grid4",    7),
    ("custom-domains/dns.jpg",      1200, 675, "tags",     7),
    ("custom-domains/ssl.jpg",      1200, 675, "shield",   7),

    # Post 8 — QR vs Link (red)
    ("qr-vs-link/hero.jpg",       1600, 900, "split",   6),
    ("qr-vs-link/surfaces.jpg",   1200, 675, "grid6",   6),
    ("qr-vs-link/fallback.jpg",   1200, 675, "card",     6),
    ("qr-vs-link/decision.jpg",   1200, 675, "flow",     6),
]

# ----- helpers -----

def gradient_bg(w: int, h: int, bg_light: str, bg_dark: str, gid: str) -> str:
    """Soft diagonal gradient background."""
    return f'''<defs>
  <linearGradient id="{gid}" x1="0%" y1="0%" x2="100%" y2="100%">
    <stop offset="0%" stop-color="{bg_light}"/>
    <stop offset="100%" stop-color="{bg_dark}"/>
  </linearGradient>
</defs>
<rect width="{w}" height="{h}" fill="url(#{gid})"/>'''

def dot_grid(w: int, h: int, color: str, opacity: float = 0.18) -> str:
    """Subtle dot grid overlay."""
    parts = []
    spacing = 40
    for x in range(spacing // 2, w, spacing):
        for y in range(spacing // 2, h, spacing):
            parts.append(f'<circle cx="{x}" cy="{y}" r="2" fill="{color}" opacity="{opacity}"/>')
    return "\n".join(parts)


# ----- templates -----

def t_dashboard(w, h, p):
    """Analytics dashboard: chart line + two info cards."""
    bg, bgd, ac, soft, fg = p
    cx, cy = w // 2, h // 2
    # chart card
    card_w, card_h = int(w * 0.6), int(h * 0.45)
    cx1, cy1 = (w - card_w) // 2, int(h * 0.18)
    # chart line points
    points = []
    pts_count = 18
    base_y = cy1 + int(card_h * 0.75)
    for i in range(pts_count):
        px = cx1 + 40 + (card_w - 80) * i / (pts_count - 1)
        py = base_y - (40 + abs(math.sin(i / 2.5) * 100) + (i * 4))
        points.append(f"{px:.0f},{py:.0f}")
    polyline_pts = " ".join(points)

    # small bar tiles below
    tile_w = int(card_w / 4) - 10
    tile_y = cy1 + card_h + 30
    tiles = []
    for i in range(4):
        tx = cx1 + i * (tile_w + 13)
        tiles.append(f'<rect x="{tx}" y="{tile_y}" width="{tile_w}" height="{int(h * 0.18)}" rx="14" fill="#fff" stroke="{soft}" stroke-width="1.5" opacity="0.95"/>')
        # bar inside
        bar_h = int((h * 0.06) + i * 12)
        tiles.append(f'<rect x="{tx + 18}" y="{tile_y + int(h * 0.18) - bar_h - 18}" width="{tile_w - 36}" height="{bar_h}" rx="6" fill="{ac}" opacity="0.85"/>')
    tiles_svg = "\n".join(tiles)

    return f'''<g>
  <rect x="{cx1}" y="{cy1}" width="{card_w}" height="{card_h}" rx="18" fill="#fff" stroke="{soft}" stroke-width="1.5" opacity="0.97"/>
  <polyline points="{polyline_pts}" stroke="{ac}" stroke-width="4" fill="none" stroke-linejoin="round" stroke-linecap="round"/>
  <polyline points="{polyline_pts} {cx1 + card_w - 40},{base_y} {cx1 + 40},{base_y}" fill="{ac}" opacity="0.12"/>
  {tiles_svg}
</g>'''


def t_stack(w, h, p):
    """Three layered translucent cards, suggesting a stack."""
    bg, bgd, ac, soft, fg = p
    card_w, card_h = int(w * 0.55), int(h * 0.18)
    cx = (w - card_w) // 2
    cy = int(h * 0.25)
    cards = []
    labels = ["Short link wrapper", "Destination URL", "UTM parameters"]
    for i, label in enumerate(labels):
        x = cx + i * 26
        y = cy + i * (card_h + 26)
        cards.append(f'<rect x="{x}" y="{y}" width="{card_w}" height="{card_h}" rx="14" fill="#fff" opacity="{0.95 - i * 0.05}" stroke="{soft}" stroke-width="1.5"/>')
        cards.append(f'<rect x="{x + 24}" y="{y + 24}" width="14" height="14" rx="3" fill="{ac}"/>')
        cards.append(f'<rect x="{x + 50}" y="{y + 26}" width="{card_w - 100}" height="10" rx="5" fill="{soft}" opacity="0.6"/>')
        cards.append(f'<rect x="{x + 50}" y="{y + 50}" width="{int((card_w - 80) * 0.6)}" height="8" rx="4" fill="{soft}" opacity="0.4"/>')
    return "<g>" + "\n".join(cards) + "</g>"


def t_tags(w, h, p):
    """Tag/chip cloud — keys and values as small pill shapes."""
    bg, bgd, ac, soft, fg = p
    rng = random.Random(42)
    chips = []
    sizes = [110, 140, 100, 170, 130, 90, 120, 160, 100, 140, 110, 130]
    rows = 4
    cols = 4
    cell_w = (w - 240) // cols
    cell_h = (h - 200) // rows
    idx = 0
    for r in range(rows):
        for c in range(cols):
            ch_w = sizes[idx % len(sizes)]
            ch_h = 38
            cx = 120 + c * cell_w + (cell_w - ch_w) // 2 + rng.randint(-15, 15)
            cy = 100 + r * cell_h + (cell_h - ch_h) // 2 + rng.randint(-10, 10)
            is_value = (idx % 3) == 0
            fill = ac if is_value else "#fff"
            stroke = ac
            text_fill = "#fff" if is_value else ac
            chips.append(f'<rect x="{cx}" y="{cy}" width="{ch_w}" height="{ch_h}" rx="19" fill="{fill}" stroke="{stroke}" stroke-width="1.5"/>')
            chips.append(f'<rect x="{cx + 18}" y="{cy + 13}" width="{ch_w - 36}" height="12" rx="6" fill="{text_fill}" opacity="0.55"/>')
            idx += 1
    return "<g>" + "\n".join(chips) + "</g>"


def t_flow(w, h, p):
    """Horizontal flow diagram with numbered nodes and arrows."""
    bg, bgd, ac, soft, fg = p
    nodes = 4
    node_r = 60
    gap = (w - 200 - nodes * 2 * node_r) // (nodes - 1)
    cy = h // 2
    parts = []
    for i in range(nodes):
        cx = 100 + node_r + i * (2 * node_r + gap)
        parts.append(f'<circle cx="{cx}" cy="{cy}" r="{node_r}" fill="#fff" stroke="{ac}" stroke-width="3"/>')
        parts.append(f'<circle cx="{cx}" cy="{cy}" r="{node_r - 18}" fill="{ac}" opacity="0.12"/>')
        # number-like dot pattern
        parts.append(f'<rect x="{cx - 18}" y="{cy - 4}" width="36" height="8" rx="4" fill="{ac}"/>')
        if i < nodes - 1:
            ax1 = cx + node_r
            ax2 = ax1 + gap
            parts.append(f'<line x1="{ax1 + 8}" y1="{cy}" x2="{ax2 - 8}" y2="{cy}" stroke="{ac}" stroke-width="3" opacity="0.6"/>')
            parts.append(f'<polygon points="{ax2 - 8},{cy} {ax2 - 18},{cy - 6} {ax2 - 18},{cy + 6}" fill="{ac}" opacity="0.6"/>')
        # caption box under each node
        parts.append(f'<rect x="{cx - 70}" y="{cy + node_r + 28}" width="140" height="12" rx="6" fill="{ac}" opacity="0.35"/>')
        parts.append(f'<rect x="{cx - 50}" y="{cy + node_r + 48}" width="100" height="8" rx="4" fill="{ac}" opacity="0.2"/>')
    return "<g>" + "\n".join(parts) + "</g>"


def t_qrcode(w, h, p):
    """Stylized QR-code-like pattern, recognizable but abstract."""
    bg, bgd, ac, soft, fg = p
    rng = random.Random(123)
    side = min(w, h) - 200
    side -= side % 21
    cx = (w - side) // 2
    cy = (h - side) // 2
    cell = side // 21
    parts = [f'<rect x="{cx}" y="{cy}" width="{side}" height="{side}" rx="20" fill="#fff" stroke="{soft}" stroke-width="2"/>']
    for r in range(21):
        for c in range(21):
            if rng.random() > 0.5:
                parts.append(f'<rect x="{cx + c * cell + 4}" y="{cy + r * cell + 4}" width="{cell - 4}" height="{cell - 4}" fill="{fg}" opacity="0.85"/>')
    # corner finder patterns
    for fcx, fcy in [(cx + cell * 1, cy + cell * 1), (cx + side - cell * 6, cy + cell * 1), (cx + cell * 1, cy + side - cell * 6)]:
        parts.append(f'<rect x="{fcx}" y="{fcy}" width="{cell * 5}" height="{cell * 5}" fill="{fg}"/>')
        parts.append(f'<rect x="{fcx + cell}" y="{fcy + cell}" width="{cell * 3}" height="{cell * 3}" fill="#fff"/>')
        parts.append(f'<rect x="{fcx + cell * 2}" y="{fcy + cell * 2}" width="{cell}" height="{cell}" fill="{fg}"/>')
    return "<g>" + "\n".join(parts) + "</g>"


def t_split(w, h, p):
    """Two-column split: left vs right comparison."""
    bg, bgd, ac, soft, fg = p
    pad = 120
    col_w = (w - pad * 3) // 2
    col_h = h - 2 * pad
    cx1 = pad
    cy = pad
    cx2 = pad * 2 + col_w
    parts = [
        f'<rect x="{cx1}" y="{cy}" width="{col_w}" height="{col_h}" rx="22" fill="#fff" stroke="{soft}" stroke-width="2"/>',
        f'<rect x="{cx2}" y="{cy}" width="{col_w}" height="{col_h}" rx="22" fill="{ac}" opacity="0.92"/>',
        # left side: small bars
        f'<rect x="{cx1 + 60}" y="{cy + 80}" width="{col_w - 120}" height="22" rx="11" fill="{ac}" opacity="0.4"/>',
        f'<rect x="{cx1 + 60}" y="{cy + 120}" width="{int((col_w - 120) * 0.7)}" height="16" rx="8" fill="{soft}" opacity="0.5"/>',
        f'<rect x="{cx1 + 60}" y="{cy + 160}" width="{int((col_w - 120) * 0.5)}" height="16" rx="8" fill="{soft}" opacity="0.4"/>',
        # left big shape
        f'<circle cx="{cx1 + col_w // 2}" cy="{cy + col_h // 2 + 60}" r="80" fill="{ac}" opacity="0.18"/>',
        f'<circle cx="{cx1 + col_w // 2}" cy="{cy + col_h // 2 + 60}" r="55" fill="{ac}" opacity="0.3"/>',
        # right side: same but inverted
        f'<rect x="{cx2 + 60}" y="{cy + 80}" width="{col_w - 120}" height="22" rx="11" fill="#fff" opacity="0.85"/>',
        f'<rect x="{cx2 + 60}" y="{cy + 120}" width="{int((col_w - 120) * 0.7)}" height="16" rx="8" fill="#fff" opacity="0.7"/>',
        f'<rect x="{cx2 + 60}" y="{cy + 160}" width="{int((col_w - 120) * 0.5)}" height="16" rx="8" fill="#fff" opacity="0.5"/>',
        f'<circle cx="{cx2 + col_w // 2}" cy="{cy + col_h // 2 + 60}" r="80" fill="#fff" opacity="0.3"/>',
        f'<circle cx="{cx2 + col_w // 2}" cy="{cy + col_h // 2 + 60}" r="55" fill="#fff" opacity="0.5"/>',
    ]
    return "<g>" + "\n".join(parts) + "</g>"


def t_scale(w, h, p):
    """Three nested squares suggesting scale/sizing."""
    bg, bgd, ac, soft, fg = p
    cx, cy = w // 2, h // 2
    sizes = [int(h * 0.7), int(h * 0.5), int(h * 0.3)]
    parts = []
    for i, s in enumerate(sizes):
        x = cx - s // 2
        y = cy - s // 2
        op = 0.18 + i * 0.16
        parts.append(f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="18" fill="{ac}" opacity="{op}"/>')
    # small dimensional ticks
    parts.append(f'<line x1="{cx - sizes[0] // 2 - 30}" y1="{cy}" x2="{cx + sizes[0] // 2 + 30}" y2="{cy}" stroke="{ac}" stroke-width="2" stroke-dasharray="6,6" opacity="0.4"/>')
    parts.append(f'<line x1="{cx}" y1="{cy - sizes[0] // 2 - 30}" x2="{cx}" y2="{cy + sizes[0] // 2 + 30}" stroke="{ac}" stroke-width="2" stroke-dasharray="6,6" opacity="0.4"/>')
    return "<g>" + "\n".join(parts) + "</g>"


def t_card(w, h, p):
    """A single content card centred, with header + body lines."""
    bg, bgd, ac, soft, fg = p
    pad_x = int(w * 0.18)
    pad_y = int(h * 0.18)
    card_w = w - 2 * pad_x
    card_h = h - 2 * pad_y
    parts = [
        f'<rect x="{pad_x}" y="{pad_y}" width="{card_w}" height="{card_h}" rx="22" fill="#fff" stroke="{soft}" stroke-width="2"/>',
        f'<rect x="{pad_x + 50}" y="{pad_y + 50}" width="160" height="14" rx="7" fill="{ac}"/>',
        f'<rect x="{pad_x + 50}" y="{pad_y + 90}" width="{card_w - 200}" height="22" rx="11" fill="{fg}" opacity="0.85"/>',
        f'<rect x="{pad_x + 50}" y="{pad_y + 130}" width="{card_w - 100}" height="14" rx="7" fill="{soft}" opacity="0.65"/>',
        f'<rect x="{pad_x + 50}" y="{pad_y + 160}" width="{card_w - 240}" height="14" rx="7" fill="{soft}" opacity="0.5"/>',
        # bottom action
        f'<rect x="{pad_x + 50}" y="{pad_y + card_h - 80}" width="180" height="44" rx="22" fill="{ac}"/>',
        f'<rect x="{pad_x + 250}" y="{pad_y + card_h - 70}" width="120" height="24" rx="12" fill="{soft}" opacity="0.5"/>',
    ]
    return "<g>" + "\n".join(parts) + "</g>"


def t_twolines(w, h, p):
    """Two line charts overlapping for comparison."""
    bg, bgd, ac, soft, fg = p
    pad = 120
    cx, cy = pad, pad + (h - 2 * pad)
    base_y = cy
    points_a, points_b = [], []
    n = 24
    for i in range(n):
        px = pad + (w - 2 * pad) * i / (n - 1)
        py_a = base_y - (50 + abs(math.sin(i / 3) * 130) + i * 8)
        py_b = base_y - (30 + abs(math.cos(i / 3.2) * 60) + i * 5)
        points_a.append(f"{px:.0f},{py_a:.0f}")
        points_b.append(f"{px:.0f},{py_b:.0f}")
    return f'''<g>
  <line x1="{pad}" y1="{base_y}" x2="{w - pad}" y2="{base_y}" stroke="{soft}" stroke-width="1.5" opacity="0.5"/>
  <line x1="{pad}" y1="{pad}" x2="{pad}" y2="{base_y}" stroke="{soft}" stroke-width="1.5" opacity="0.5"/>
  <polyline points="{" ".join(points_a)}" stroke="{ac}" stroke-width="4" fill="none" stroke-linejoin="round"/>
  <polyline points="{" ".join(points_b)}" stroke="{soft}" stroke-width="3" fill="none" stroke-linejoin="round" stroke-dasharray="8,8"/>
</g>'''


def t_map(w, h, p):
    """Abstract dotted world-map shape."""
    bg, bgd, ac, soft, fg = p
    rng = random.Random(7)
    parts = []
    for _ in range(280):
        x = rng.randint(80, w - 80)
        y = rng.randint(80, h - 80)
        # eyeballed continent-ish weighting
        if (300 < x < 700 and 200 < y < 500) or (900 < x < 1100 and 200 < y < 600):
            r = rng.randint(4, 9)
            op = rng.uniform(0.35, 0.85)
            parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{ac}" opacity="{op:.2f}"/>')
        else:
            if rng.random() < 0.4:
                r = rng.randint(2, 5)
                op = rng.uniform(0.15, 0.35)
                parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{ac}" opacity="{op:.2f}"/>')
    return "<g>" + "\n".join(parts) + "</g>"


def t_histogram(w, h, p):
    """Bar histogram with violet bars."""
    bg, bgd, ac, soft, fg = p
    pad = 120
    n = 24
    bar_gap = 12
    avail_w = w - 2 * pad
    bar_w = (avail_w - (n - 1) * bar_gap) // n
    base_y = h - pad
    parts = [
        f'<line x1="{pad}" y1="{base_y}" x2="{w - pad}" y2="{base_y}" stroke="{soft}" stroke-width="1.5" opacity="0.5"/>',
    ]
    rng = random.Random(11)
    for i in range(n):
        # working-hours peak in the middle
        height_norm = 0.25 + 0.7 * math.exp(-((i - 13) / 5) ** 2) + 0.18 * math.exp(-((i - 21) / 2.2) ** 2)
        bh = int((h - 2 * pad) * height_norm * rng.uniform(0.85, 1.05))
        bx = pad + i * (bar_w + bar_gap)
        parts.append(f'<rect x="{bx}" y="{base_y - bh}" width="{bar_w}" height="{bh}" rx="4" fill="{ac}" opacity="{0.45 + height_norm * 0.55:.2f}"/>')
    return "<g>" + "\n".join(parts) + "</g>"


def t_shield(w, h, p):
    """Shield silhouette centered, with subtle network behind."""
    bg, bgd, ac, soft, fg = p
    cx, cy = w // 2, h // 2
    sh_w = int(h * 0.55)
    sh_h = int(h * 0.65)
    sx, sy = cx - sh_w // 2, cy - sh_h // 2
    rng = random.Random(33)
    # network lines
    nodes = []
    parts = []
    for _ in range(14):
        nx = rng.randint(80, w - 80)
        ny = rng.randint(80, h - 80)
        nodes.append((nx, ny))
    for a in nodes:
        for b in nodes:
            if a is b:
                continue
            dist = math.hypot(a[0] - b[0], a[1] - b[1])
            if dist < 280:
                parts.append(f'<line x1="{a[0]}" y1="{a[1]}" x2="{b[0]}" y2="{b[1]}" stroke="{ac}" stroke-width="1" opacity="0.15"/>')
    for nx, ny in nodes:
        parts.append(f'<circle cx="{nx}" cy="{ny}" r="4" fill="{ac}" opacity="0.45"/>')

    shield_path = (
        f"M {sx + sh_w // 2} {sy} "
        f"L {sx + sh_w} {sy + sh_h // 6} "
        f"L {sx + sh_w} {sy + int(sh_h * 0.55)} "
        f"Q {sx + sh_w} {sy + sh_h} {sx + sh_w // 2} {sy + sh_h} "
        f"Q {sx} {sy + sh_h} {sx} {sy + int(sh_h * 0.55)} "
        f"L {sx} {sy + sh_h // 6} Z"
    )
    parts.append(f'<path d="{shield_path}" fill="#fff" stroke="{ac}" stroke-width="4"/>')
    parts.append(f'<path d="{shield_path}" fill="{ac}" opacity="0.15"/>')
    # check inside
    check_pts = (
        f"M {cx - 36} {cy} "
        f"L {cx - 8} {cy + 28} "
        f"L {cx + 40} {cy - 24}"
    )
    parts.append(f'<path d="{check_pts}" stroke="{ac}" stroke-width="8" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')
    return "<g>" + "\n".join(parts) + "</g>"


def t_grid4(w, h, p):
    """2x2 grid of card tiles."""
    bg, bgd, ac, soft, fg = p
    pad = 100
    gap = 40
    cell_w = (w - 2 * pad - gap) // 2
    cell_h = (h - 2 * pad - gap) // 2
    parts = []
    icons = ["circle", "triangle", "square", "diamond"]
    for i, ic in enumerate(icons):
        col = i % 2
        row = i // 2
        x = pad + col * (cell_w + gap)
        y = pad + row * (cell_h + gap)
        parts.append(f'<rect x="{x}" y="{y}" width="{cell_w}" height="{cell_h}" rx="20" fill="#fff" stroke="{soft}" stroke-width="2"/>')
        ix, iy = x + cell_w // 2, y + cell_h // 2 - 20
        if ic == "circle":
            parts.append(f'<circle cx="{ix}" cy="{iy}" r="48" fill="{ac}" opacity="0.85"/>')
        elif ic == "triangle":
            parts.append(f'<polygon points="{ix},{iy - 50} {ix + 48},{iy + 32} {ix - 48},{iy + 32}" fill="{ac}" opacity="0.85"/>')
        elif ic == "square":
            parts.append(f'<rect x="{ix - 45}" y="{iy - 45}" width="90" height="90" rx="12" fill="{ac}" opacity="0.85"/>')
        else:
            parts.append(f'<polygon points="{ix},{iy - 56} {ix + 56},{iy} {ix},{iy + 56} {ix - 56},{iy}" fill="{ac}" opacity="0.85"/>')
        parts.append(f'<rect x="{x + 30}" y="{y + cell_h - 60}" width="{cell_w - 60}" height="14" rx="7" fill="{ac}" opacity="0.4"/>')
        parts.append(f'<rect x="{x + 30}" y="{y + cell_h - 36}" width="{int((cell_w - 60) * 0.6)}" height="10" rx="5" fill="{soft}" opacity="0.4"/>')
    return "<g>" + "\n".join(parts) + "</g>"


def t_layers(w, h, p):
    """Three horizontal layers with arrows passing through."""
    bg, bgd, ac, soft, fg = p
    layer_h = int(h * 0.13)
    gap = int(h * 0.06)
    total = 3 * layer_h + 2 * gap
    start_y = (h - total) // 2
    parts = []
    for i in range(3):
        ly = start_y + i * (layer_h + gap)
        parts.append(f'<rect x="100" y="{ly}" width="{w - 200}" height="{layer_h}" rx="14" fill="#fff" stroke="{soft}" stroke-width="2" opacity="0.95"/>')
        parts.append(f'<rect x="140" y="{ly + 20}" width="160" height="14" rx="7" fill="{ac}" opacity="0.55"/>')
        # check mark on right
        cmx = w - 200
        cmy = ly + layer_h // 2
        parts.append(f'<circle cx="{cmx}" cy="{cmy}" r="22" fill="{ac}"/>')
        parts.append(f'<path d="M {cmx - 8} {cmy} L {cmx - 2} {cmy + 6} L {cmx + 10} {cmy - 6}" stroke="#fff" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')
    # arrow passing down through the layers
    parts.insert(0, f'<line x1="{w // 2}" y1="{start_y - 30}" x2="{w // 2}" y2="{start_y + total + 30}" stroke="{ac}" stroke-width="3" stroke-dasharray="10,10" opacity="0.5"/>')
    return "<g>" + "\n".join(parts) + "</g>"


def t_alert(w, h, p):
    """Browser-window mockup with safety interstitial."""
    bg, bgd, ac, soft, fg = p
    pad = 110
    box_w = w - 2 * pad
    box_h = h - 2 * pad
    parts = [
        f'<rect x="{pad}" y="{pad}" width="{box_w}" height="{box_h}" rx="18" fill="#fff" stroke="{soft}" stroke-width="2"/>',
        # browser bar
        f'<rect x="{pad}" y="{pad}" width="{box_w}" height="56" rx="18" fill="{soft}" opacity="0.35"/>',
        f'<circle cx="{pad + 24}" cy="{pad + 28}" r="6" fill="#ff5f57"/>',
        f'<circle cx="{pad + 44}" cy="{pad + 28}" r="6" fill="#febc2e"/>',
        f'<circle cx="{pad + 64}" cy="{pad + 28}" r="6" fill="#28c840"/>',
        f'<rect x="{pad + 120}" y="{pad + 18}" width="{box_w - 200}" height="20" rx="10" fill="#fff"/>',
        # warning shield
        f'<polygon points="{w // 2},{pad + 130} {w // 2 + 80},{pad + 280} {w // 2 - 80},{pad + 280}" fill="{ac}" opacity="0.9"/>',
        f'<rect x="{w // 2 - 6}" y="{pad + 180}" width="12" height="60" rx="6" fill="#fff"/>',
        f'<circle cx="{w // 2}" cy="{pad + 258}" r="8" fill="#fff"/>',
        # caption bars
        f'<rect x="{pad + box_w // 2 - 220}" y="{pad + 320}" width="440" height="20" rx="10" fill="{fg}" opacity="0.85"/>',
        f'<rect x="{pad + box_w // 2 - 180}" y="{pad + 360}" width="360" height="14" rx="7" fill="{soft}" opacity="0.6"/>',
        f'<rect x="{pad + box_w // 2 - 80}" y="{pad + box_h - 90}" width="160" height="40" rx="20" fill="{ac}"/>',
    ]
    return "<g>" + "\n".join(parts) + "</g>"


def t_billboard(w, h, p):
    """Billboard silhouette with branded short URL."""
    bg, bgd, ac, soft, fg = p
    bb_w = int(w * 0.6)
    bb_h = int(h * 0.45)
    bx = (w - bb_w) // 2
    by = int(h * 0.18)
    parts = [
        f'<rect x="{bx - 8}" y="{by - 8}" width="{bb_w + 16}" height="{bb_h + 16}" rx="14" fill="{fg}" opacity="0.95"/>',
        f'<rect x="{bx}" y="{by}" width="{bb_w}" height="{bb_h}" rx="8" fill="#fff"/>',
        f'<rect x="{bx + 60}" y="{by + 40}" width="180" height="20" rx="10" fill="{ac}"/>',
        f'<rect x="{bx + 60}" y="{by + 80}" width="{bb_w - 120}" height="42" rx="10" fill="{fg}" opacity="0.85"/>',
        f'<rect x="{bx + 60}" y="{by + 140}" width="{bb_w - 200}" height="18" rx="9" fill="{soft}" opacity="0.6"/>',
        # branded URL inside billboard
        f'<rect x="{bx + 60}" y="{by + bb_h - 100}" width="{bb_w - 120}" height="60" rx="14" fill="{ac}" opacity="0.15"/>',
        f'<rect x="{bx + 80}" y="{by + bb_h - 80}" width="{bb_w - 220}" height="20" rx="10" fill="{ac}"/>',
        # support posts
        f'<rect x="{bx + bb_w // 4}" y="{by + bb_h + 16}" width="14" height="{int(h * 0.25)}" fill="{fg}" opacity="0.7"/>',
        f'<rect x="{bx + bb_w - bb_w // 4 - 14}" y="{by + bb_h + 16}" width="14" height="{int(h * 0.25)}" fill="{fg}" opacity="0.7"/>',
    ]
    return "<g>" + "\n".join(parts) + "</g>"


def t_bars(w, h, p):
    """Horizontal bar chart, 4 bars."""
    bg, bgd, ac, soft, fg = p
    pad = 140
    bar_h = 60
    gap = 28
    n = 4
    avail_h = h - 2 * pad
    parts = []
    lengths = [0.95, 0.7, 0.5, 0.35]
    for i in range(n):
        y = pad + i * (bar_h + gap)
        # label region
        parts.append(f'<rect x="{pad}" y="{y + bar_h // 2 - 7}" width="180" height="14" rx="7" fill="{soft}" opacity="0.55"/>')
        # bar
        bar_x = pad + 220
        bar_l = int((w - bar_x - pad) * lengths[i])
        parts.append(f'<rect x="{bar_x}" y="{y}" width="{bar_l}" height="{bar_h}" rx="10" fill="{ac}" opacity="{0.95 - i * 0.15}"/>')
    return "<g>" + "\n".join(parts) + "</g>"


def t_form(w, h, p):
    """Form / settings panel mockup."""
    bg, bgd, ac, soft, fg = p
    pad = 140
    form_w = w - 2 * pad
    form_h = h - 2 * pad
    parts = [
        f'<rect x="{pad}" y="{pad}" width="{form_w}" height="{form_h}" rx="22" fill="#fff" stroke="{soft}" stroke-width="2"/>',
        f'<rect x="{pad + 50}" y="{pad + 50}" width="220" height="18" rx="9" fill="{ac}"/>',
        # input field
        f'<rect x="{pad + 50}" y="{pad + 110}" width="{form_w - 100}" height="56" rx="12" fill="{soft}" opacity="0.18"/>',
        f'<rect x="{pad + 70}" y="{pad + 132}" width="280" height="14" rx="7" fill="{fg}" opacity="0.65"/>',
        # status row
        f'<rect x="{pad + 50}" y="{pad + 200}" width="{form_w - 100}" height="50" rx="12" fill="{ac}" opacity="0.13"/>',
        f'<circle cx="{pad + 78}" cy="{pad + 225}" r="10" fill="{ac}"/>',
        f'<rect x="{pad + 102}" y="{pad + 217}" width="240" height="16" rx="8" fill="{ac}" opacity="0.85"/>',
        # button
        f'<rect x="{pad + 50}" y="{pad + form_h - 90}" width="160" height="44" rx="22" fill="{ac}"/>',
    ]
    return "<g>" + "\n".join(parts) + "</g>"


def t_timeline(w, h, p):
    """Vertical timeline with dots and entries."""
    bg, bgd, ac, soft, fg = p
    line_x = int(w * 0.22)
    pad_y = 100
    rows = 5
    row_h = (h - 2 * pad_y) // (rows - 1)
    parts = [
        f'<line x1="{line_x}" y1="{pad_y}" x2="{line_x}" y2="{h - pad_y}" stroke="{ac}" stroke-width="3"/>',
    ]
    for i in range(rows):
        y = pad_y + i * row_h
        parts.append(f'<circle cx="{line_x}" cy="{y}" r="14" fill="#fff" stroke="{ac}" stroke-width="3"/>')
        # entry box
        ex = line_x + 50
        ew = w - ex - 100
        parts.append(f'<rect x="{ex}" y="{y - 36}" width="{ew}" height="72" rx="14" fill="#fff" stroke="{soft}" stroke-width="1.5"/>')
        parts.append(f'<rect x="{ex + 24}" y="{y - 16}" width="{int(ew * 0.5)}" height="14" rx="7" fill="{fg}" opacity="0.85"/>')
        parts.append(f'<rect x="{ex + 24}" y="{y + 8}" width="{int(ew * 0.3)}" height="10" rx="5" fill="{soft}" opacity="0.6"/>')
        # avatar
        parts.append(f'<circle cx="{ex + ew - 36}" cy="{y}" r="18" fill="{ac}" opacity="0.7"/>')
    return "<g>" + "\n".join(parts) + "</g>"


def t_grid6(w, h, p):
    """3x2 grid of surface icons."""
    bg, bgd, ac, soft, fg = p
    pad = 80
    gap = 30
    cols = 3
    rows = 2
    cell_w = (w - 2 * pad - (cols - 1) * gap) // cols
    cell_h = (h - 2 * pad - (rows - 1) * gap) // rows
    parts = []
    for i in range(cols * rows):
        col = i % cols
        row = i // cols
        x = pad + col * (cell_w + gap)
        y = pad + row * (cell_h + gap)
        parts.append(f'<rect x="{x}" y="{y}" width="{cell_w}" height="{cell_h}" rx="18" fill="#fff" stroke="{soft}" stroke-width="2"/>')
        ix, iy = x + cell_w // 2, y + cell_h // 2 - 10
        # vary icon by index
        if i % 4 == 0:
            parts.append(f'<rect x="{ix - 40}" y="{iy - 30}" width="80" height="60" rx="8" fill="{ac}" opacity="0.85"/>')
        elif i % 4 == 1:
            parts.append(f'<circle cx="{ix}" cy="{iy}" r="40" fill="{ac}" opacity="0.85"/>')
        elif i % 4 == 2:
            parts.append(f'<polygon points="{ix},{iy - 42} {ix + 40},{iy + 28} {ix - 40},{iy + 28}" fill="{ac}" opacity="0.85"/>')
        else:
            parts.append(f'<polygon points="{ix},{iy - 44} {ix + 44},{iy} {ix},{iy + 44} {ix - 44},{iy}" fill="{ac}" opacity="0.85"/>')
        # bottom badge
        parts.append(f'<rect x="{x + cell_w // 2 - 50}" y="{y + cell_h - 36}" width="100" height="18" rx="9" fill="{ac}" opacity="0.4"/>')
    return "<g>" + "\n".join(parts) + "</g>"


TEMPLATES = {
    "dashboard": t_dashboard,
    "stack": t_stack,
    "tags": t_tags,
    "flow": t_flow,
    "qrcode": t_qrcode,
    "split": t_split,
    "scale": t_scale,
    "card": t_card,
    "twolines": t_twolines,
    "map": t_map,
    "histogram": t_histogram,
    "shield": t_shield,
    "grid4": t_grid4,
    "layers": t_layers,
    "alert": t_alert,
    "billboard": t_billboard,
    "bars": t_bars,
    "form": t_form,
    "timeline": t_timeline,
    "grid6": t_grid6,
}


def make_svg(width: int, height: int, template: str, palette_idx: int, seed: int) -> str:
    """Compose a full SVG document."""
    random.seed(seed)
    palette = PALETTES[palette_idx]
    bg_light, bg_dark, ac, soft, fg = palette
    gid = f"g{seed}"
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
        f'role="img" preserveAspectRatio="xMidYMid slice">',
        gradient_bg(width, height, bg_light, bg_dark, gid),
        dot_grid(width, height, ac),
    ]
    if template in TEMPLATES:
        parts.append(TEMPLATES[template](width, height, palette))
    parts.append("</svg>")
    return "\n".join(parts)


def main() -> int:
    root = Path(__file__).resolve().parent.parent / "assets" / "images"
    print(f"Writing {len(IMAGES)} SVGs into {root}/")
    written = 0
    for index, (rel, w, h, tpl, pi) in enumerate(IMAGES):
        target = root / rel
        target = target.with_suffix(".svg")
        target.parent.mkdir(parents=True, exist_ok=True)
        svg = make_svg(w, h, tpl, pi, seed=1000 + index)
        target.write_text(svg, encoding="utf-8")
        written += 1
        print(f"  ok {target.relative_to(root.parent.parent)} ({len(svg) // 1024} KB)")
    print(f"Done: {written} SVGs.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
