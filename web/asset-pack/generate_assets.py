#!/usr/bin/env python3
"""
PROJECT TADKA — Visual Asset Generator v1
Emits the complete beta art pack: SVG assets + tokens + self-contained preview.html
Style: "Midnight Bazaar" — vintage spice-trade labels on a night-market sky.
Flat 2-tone illustration, parchment cards, brass accents, sunburst signatures.
Re-run any time; Opus extends by adding entries to ICONS / UTENSILS dicts.
"""

import os, json, shutil, math

OUT = "/mnt/user-data/outputs/tadka-assets"

# ---------------------------------------------------------------- TOKENS
T = {
    "bg":        "#171426",  # Midnight Bazaar — night-market sky
    "surface":   "#241F38",  # Awning — panels
    "surface2":  "#2E2846",  # raised panel
    "parchment": "#F5E9D0",  # spice-label paper
    "parchDark": "#E7D6B4",  # paper shade
    "ink":       "#2B2438",  # text on parchment
    "brass":     "#D9A441",  # coins, borders, CTAs
    "brassDark": "#A87A2B",
    "cream":     "#FFF6E3",  # highlights
    "textHi":    "#F2E8D5",
    "textLo":    "#9A92B0",
    "danger":    "#E85A4F",
    "good":      "#8FBF6B",
    "families": {
        "spicy": {"c": "#E23B22", "d": "#A32612", "name": "Spicy"},
        "sweet": {"c": "#E8A020", "d": "#B0740E", "name": "Sweet"},
        "sour":  {"c": "#7CB342", "d": "#557F2B", "name": "Sour"},
        "salty": {"c": "#4A90D9", "d": "#2F639C", "name": "Salty"},
        "umami": {"c": "#8E5AA8", "d": "#623A78", "name": "Umami"},
    },
    "rarity": {"common": "#8A8494", "uncommon": "#7CB342", "rare": "#D9A441"},
}

def ensure_dirs():
    for d in ["", "cards", "ingredients", "utensils", "critics", "backdrops", "brand", "ui"]:
        os.makedirs(os.path.join(OUT, d), exist_ok=True)

def write(path, content):
    with open(os.path.join(OUT, path), "w") as f:
        f.write(content)

def svg(w, h, inner, vb=None):
    vb = vb or f"0 0 {w} {h}"
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" '
            f'width="{w}" height="{h}">{inner}</svg>')

# ---------------------------------------------------------------- SUNBURST (signature)
def sunburst(cx, cy, r_in, r_out, n, color, opacity=0.35):
    rays = []
    for i in range(n):
        a0 = (2 * math.pi / n) * i
        a1 = a0 + (2 * math.pi / n) * 0.5
        x0, y0 = cx + r_in * math.cos(a0), cy + r_in * math.sin(a0)
        x1, y1 = cx + r_out * math.cos(a0), cy + r_out * math.sin(a0)
        x2, y2 = cx + r_out * math.cos(a1), cy + r_out * math.sin(a1)
        x3, y3 = cx + r_in * math.cos(a1), cy + r_in * math.sin(a1)
        rays.append(f'<path d="M{x0:.1f} {y0:.1f} L{x1:.1f} {y1:.1f} '
                    f'L{x2:.1f} {y2:.1f} L{x3:.1f} {y3:.1f} Z" '
                    f'fill="{color}" opacity="{opacity}"/>')
    return "".join(rays)

# ---------------------------------------------------------------- INGREDIENT ICONS
# Each icon: flat 2-tone + cream sparkle, drawn in a 100x100 box, silhouette-first.
# fam color = F, dark shade = D injected per family at compose time.
CREAM = T["cream"]
STEM = "#557F2B"  # universal stem green
def icon_defs():
    return {
    # ---- SPICY
    "red_chili": '''
      <path d="M28 72 C20 66 18 52 30 40 C42 28 62 22 74 26 C70 40 62 58 48 68 C40 74 33 75 28 72 Z" fill="{F}"/>
      <path d="M32 66 C40 62 54 52 62 38" stroke="{D}" stroke-width="5" fill="none" stroke-linecap="round"/>
      <path d="M72 26 C74 18 82 16 86 18 C84 26 78 30 72 30 Z" fill="'''+STEM+'''"/>
      <circle cx="34" cy="58" r="3.5" fill="'''+CREAM+'''" opacity=".8"/>''',
    "birds_eye_chili": '''
      <path d="M30 78 C24 70 28 56 40 46 C50 38 60 34 66 36 C64 48 56 64 44 74 C38 78 33 80 30 78 Z" fill="{F}"/>
      <path d="M50 52 C44 44 48 30 60 20 C68 14 76 12 80 14 C78 26 72 40 62 48 C58 51 53 54 50 52 Z" fill="{D}"/>
      <path d="M62 38 C64 32 70 30 74 31 C73 37 68 40 63 41 Z" fill="'''+STEM+'''"/>
      <path d="M78 12 C80 7 85 6 88 7 C87 12 83 15 79 16 Z" fill="'''+STEM+'''"/>''',
    "scotch_bonnet": '''
      <path d="M25 58 C25 44 36 36 50 36 C64 36 75 44 75 58 C75 64 71 70 64 72 C60 76 54 77 50 74 C46 77 40 76 36 72 C29 70 25 64 25 58 Z" fill="{F}"/>
      <path d="M36 70 C33 64 33 54 38 46" stroke="{D}" stroke-width="5" fill="none" stroke-linecap="round"/>
      <path d="M62 70 C66 64 66 54 61 46" stroke="{D}" stroke-width="5" fill="none" stroke-linecap="round"/>
      <path d="M46 36 C46 28 50 22 58 20 C60 26 56 33 52 36 Z" fill="'''+STEM+'''"/>
      <circle cx="42" cy="52" r="3.5" fill="'''+CREAM+'''" opacity=".8"/>''',
    "mustard_seed": '''
      <circle cx="38" cy="56" r="12" fill="{F}"/><circle cx="60" cy="48" r="10" fill="{D}"/>
      <circle cx="52" cy="68" r="11" fill="{F}"/><circle cx="68" cy="64" r="8" fill="{F}"/>
      <circle cx="44" cy="38" r="8" fill="{D}"/>
      <path d="M62 30 C66 20 76 16 84 18 C82 28 74 34 64 34 Z" fill="'''+STEM+'''"/>
      <circle cx="35" cy="52" r="3" fill="'''+CREAM+'''" opacity=".85"/>''',
    "star_anise": '''
      <g fill="{F}">''' + "".join(
        f'<ellipse cx="50" cy="30" rx="9" ry="20" transform="rotate({a} 50 50)"/>'
        for a in range(0, 360, 45)) + '''</g>
      <g fill="{D}">''' + "".join(
        f'<ellipse cx="50" cy="33" rx="4" ry="12" transform="rotate({a} 50 50)"/>'
        for a in range(0, 360, 45)) + '''</g>
      <circle cx="50" cy="50" r="7" fill="{D}"/><circle cx="48" cy="48" r="2.5" fill="'''+CREAM+'''" opacity=".9"/>''',
    # ---- SWEET
    "honey_pot": '''
      <path d="M28 46 C28 36 38 30 50 30 C62 30 72 36 72 46 C72 62 64 74 50 74 C36 74 28 62 28 46 Z" fill="{F}"/>
      <rect x="34" y="26" width="32" height="10" rx="5" fill="{D}"/>
      <path d="M42 74 C42 80 46 84 50 84 C54 84 58 80 58 74 Z" fill="{D}"/>
      <path d="M32 48 C34 58 40 66 48 68" stroke="'''+CREAM+'''" stroke-width="4" fill="none" opacity=".55" stroke-linecap="round"/>''',
    "palm_sugar": '''
      <path d="M30 62 C30 52 39 46 50 46 C61 46 70 52 70 62 L70 68 C70 71 67 72 64 72 L36 72 C33 72 30 71 30 68 Z" fill="{F}"/>
      <path d="M36 44 C36 36 42 31 50 31 C58 31 64 36 64 44 L64 46 L36 46 Z" fill="{D}"/>
      <path d="M50 30 C46 18 34 14 24 18 C30 28 40 32 50 30 Z" fill="'''+STEM+'''"/>
      <circle cx="40" cy="56" r="3.5" fill="'''+CREAM+'''" opacity=".8"/>''',
    "maple": '''
      <path d="M50 20 L57 34 L72 30 L64 44 L78 52 L62 56 L64 72 L50 62 L36 72 L38 56 L22 52 L36 44 L28 30 L43 34 Z" fill="{F}"/>
      <path d="M50 30 L50 60" stroke="{D}" stroke-width="4" stroke-linecap="round"/>
      <path d="M50 62 L50 80" stroke="{D}" stroke-width="5" stroke-linecap="round"/>
      <path d="M40 46 L60 46" stroke="{D}" stroke-width="3.5" stroke-linecap="round"/>''',
    "jaggery": '''
      <path d="M32 66 L38 44 C39 40 43 38 47 38 L53 38 C57 38 61 40 62 44 L68 66 C69 70 66 73 62 73 L38 73 C34 73 31 70 32 66 Z" fill="{F}"/>
      <path d="M40 50 L60 50" stroke="{D}" stroke-width="4" stroke-linecap="round"/>
      <path d="M37 60 L63 60" stroke="{D}" stroke-width="4" stroke-linecap="round"/>
      <circle cx="45" cy="44" r="3" fill="'''+CREAM+'''" opacity=".85"/>''',
    # ---- SOUR
    "lemon": '''
      <path d="M22 50 C22 38 34 30 50 30 C66 30 78 38 78 50 C78 62 66 70 50 70 C34 70 22 62 22 50 Z" fill="{F}"/>
      <path d="M18 50 C20 48 22 48 24 50 C22 52 20 52 18 50 Z" fill="{F}"/>
      <path d="M76 50 C78 48 80 48 82 50 C80 52 78 52 76 50 Z" fill="{F}"/>
      <path d="M30 44 C36 38 46 36 54 38" stroke="'''+CREAM+'''" stroke-width="4" fill="none" opacity=".6" stroke-linecap="round"/>
      <path d="M60 28 C64 18 76 16 84 20 C78 30 68 32 60 28 Z" fill="'''+STEM+'''"/>''',
    "fermented_lime": '''
      <circle cx="50" cy="54" r="24" fill="{F}"/>
      <circle cx="50" cy="54" r="15" fill="{D}"/>
      <g stroke="{F}" stroke-width="3">''' + "".join(
        f'<line x1="50" y1="54" x2="{50+13*math.cos(math.radians(a)):.0f}" y2="{54+13*math.sin(math.radians(a)):.0f}"/>'
        for a in range(0, 360, 45)) + '''</g>
      <circle cx="32" cy="34" r="4" fill="{F}" opacity=".7"/><circle cx="70" cy="30" r="3" fill="{F}" opacity=".7"/>
      <circle cx="62" cy="40" r="2.5" fill="'''+CREAM+'''" opacity=".8"/>
      <path d="M54 30 C58 22 68 20 74 24 C70 32 60 34 54 30 Z" fill="'''+STEM+'''"/>''',
    "tamarind": '''
      <path d="M24 56 C28 44 40 38 52 40 C66 42 76 50 76 60 C76 66 70 69 64 67 C56 64 52 58 44 56 C36 54 30 58 24 56 Z" fill="{F}"/>
      <path d="M34 52 C40 48 50 48 58 52" stroke="{D}" stroke-width="4" fill="none" stroke-linecap="round"/>
      <circle cx="40" cy="55" r="2.8" fill="{D}"/><circle cx="54" cy="57" r="2.8" fill="{D}"/><circle cx="66" cy="60" r="2.8" fill="{D}"/>
      <path d="M22 54 C18 48 20 42 26 40 C28 46 26 51 22 54 Z" fill="'''+STEM+'''"/>''',
    # ---- SALTY
    "salt_crystal": '''
      <path d="M35 40 L55 34 L62 52 L42 58 Z" fill="{F}"/>
      <path d="M42 58 L62 52 L58 70 L40 74 Z" fill="{D}"/>
      <path d="M28 56 L40 52 L44 66 L32 70 Z" fill="{F}"/>
      <path d="M58 40 L72 44 L68 58 L60 54 Z" fill="{D}"/>
      <path d="M40 40 L48 38" stroke="'''+CREAM+'''" stroke-width="3.5" stroke-linecap="round" opacity=".9"/>''',
    "sea_salt_shaker": '''
      <path d="M38 40 L62 40 L66 74 C66 78 62 80 50 80 C38 80 34 78 34 74 Z" fill="{F}"/>
      <path d="M40 30 C40 24 60 24 60 30 L61 40 L39 40 Z" fill="{D}"/>
      <circle cx="46" cy="30" r="2" fill="'''+CREAM+'''"/><circle cx="54" cy="30" r="2" fill="'''+CREAM+'''"/><circle cx="50" cy="34" r="2" fill="'''+CREAM+'''"/>
      <path d="M40 52 L60 52" stroke="'''+CREAM+'''" stroke-width="4" opacity=".5" stroke-linecap="round"/>''',
    # ---- UMAMI
    "dashi": '''
      <path d="M24 52 L76 52 C76 66 66 76 50 76 C34 76 24 66 24 52 Z" fill="{F}"/>
      <path d="M24 52 L76 52 C76 56 66 58 50 58 C34 58 24 56 24 52 Z" fill="{D}"/>
      <path d="M40 44 C36 38 40 34 38 28" stroke="{D}" stroke-width="4.5" fill="none" stroke-linecap="round" opacity=".9"/>
      <path d="M58 44 C54 38 58 34 56 28" stroke="{D}" stroke-width="4.5" fill="none" stroke-linecap="round" opacity=".9"/>
      <circle cx="34" cy="68" r="3" fill="'''+CREAM+'''" opacity=".6"/>''',
    "shiitake": '''
      <path d="M22 50 C22 36 34 28 50 28 C66 28 78 36 78 50 C78 54 74 56 70 56 L30 56 C26 56 22 54 22 50 Z" fill="{F}"/>
      <path d="M30 52 C30 44 38 38 50 38" stroke="'''+CREAM+'''" stroke-width="4" fill="none" opacity=".5" stroke-linecap="round"/>
      <path d="M42 56 L40 74 C40 78 44 80 50 80 C56 80 60 78 60 74 L58 56 Z" fill="{D}"/>
      <g stroke="{D}" stroke-width="2.5" opacity=".8"><line x1="34" y1="56" x2="34" y2="60"/><line x1="50" y1="56" x2="50" y2="61"/><line x1="66" y1="56" x2="66" y2="60"/></g>''',
    }

FAMILY_DEFAULT_ICON = {"spicy": "red_chili", "sweet": "honey_pot", "sour": "lemon",
                       "salty": "salt_crystal", "umami": "shiitake"}
INGREDIENT_FAMILY = {
    "red_chili": "spicy", "birds_eye_chili": "spicy", "scotch_bonnet": "spicy",
    "mustard_seed": "spicy", "star_anise": "spicy",
    "honey_pot": "sweet", "palm_sugar": "sweet", "maple": "sweet", "jaggery": "sweet",
    "lemon": "sour", "fermented_lime": "sour", "tamarind": "sour",
    "salt_crystal": "salty", "sea_salt_shaker": "salty",
    "dashi": "umami", "shiitake": "umami",
}

def ingredient_icon_svg(name, boxed=False):
    fam = INGREDIENT_FAMILY[name]
    F, D = T["families"][fam]["c"], T["families"][fam]["d"]
    inner = icon_defs()[name].replace("{F}", F).replace("{D}", D)
    if boxed:
        inner = sunburst(50, 50, 20, 46, 12, F, 0.18) + inner
    return svg(100, 100, inner)

# ---------------------------------------------------------------- CARD FRAME (signature asset)
def scallop_edge(y, w, n, r, fill):
    seg = w / n
    d = f"M0 {y} "
    for i in range(n):
        d += f"a{seg/2:.1f} {r} 0 0 0 {seg:.1f} 0 "
    d += f"L{w} {y-30} L0 {y-30} Z"
    return f'<path d="{d}" fill="{fill}"/>'

def card_svg(fam, rank, icon_name, display):
    f = T["families"][fam]; F, D = f["c"], f["d"]
    W, H = 180, 252
    icon_inner = icon_defs()[icon_name].replace("{F}", F).replace("{D}", D)
    parts = [
        f'<rect width="{W}" height="{H}" rx="14" fill="{T["parchment"]}"/>',
        f'<rect x="4" y="4" width="{W-8}" height="{H-8}" rx="11" fill="none" stroke="{T["parchDark"]}" stroke-width="2"/>',
        # family band with scalloped ticket edge
        f'<path d="M4 4 H{W-4} a10 10 0 0 1 10 10 V50 H-6 V14 a10 10 0 0 1 10-10 Z" fill="{F}" transform="translate(0,0)"/>'
        .replace("-6", "4"),
        scallop_edge(58, W, 9, 8, F),
        f'<text x="14" y="38" font-family="Fraunces, Georgia, serif" font-size="30" font-weight="700" fill="{T["cream"]}">{rank}</text>',
        f'<text x="{W-14}" y="36" text-anchor="end" font-family="Inter, sans-serif" font-size="11" letter-spacing="2" font-weight="700" fill="{T["cream"]}" opacity=".9">{f["name"].upper()}</text>',
        # sunburst + icon
        f'<g transform="translate(40,74) scale(1.0)">{sunburst(50, 52, 22, 50, 12, F, 0.16)}{icon_inner}</g>',
        # footer
        f'<rect x="14" y="{H-46}" width="{W-28}" height="1.5" fill="{D}" opacity=".35"/>',
        f'<text x="{W/2}" y="{H-24}" text-anchor="middle" font-family="Fraunces, Georgia, serif" font-size="15" font-weight="600" fill="{T["ink"]}">{display}</text>',
    ]
    return svg(W, H, "".join(parts))

# ---------------------------------------------------------------- UTENSIL BADGES
def utensil_defs():
    P, I, B = T["parchment"], T["ink"], T["brass"]
    return {
    "iron_tawa":      ("common",   f'<circle cx="50" cy="54" r="22" fill="{I}"/><circle cx="50" cy="54" r="16" fill="#3A3350"/><rect x="68" y="50" width="20" height="7" rx="3.5" fill="{I}"/>'),
    "mint_garnish":   ("common",   f'<g fill="{T["families"]["sour"]["c"]}"><ellipse cx="42" cy="52" rx="9" ry="16" transform="rotate(-25 42 52)"/><ellipse cx="58" cy="52" rx="9" ry="16" transform="rotate(25 58 52)"/><ellipse cx="50" cy="42" rx="8" ry="15"/></g><path d="M50 60 L50 76" stroke="{T["families"]["sour"]["d"]}" stroke-width="4" stroke-linecap="round"/>'),
    "salt_cellar":    ("common",   f'<path d="M40 42 L60 42 L64 72 C64 76 60 78 50 78 C40 78 36 76 36 72 Z" fill="{P}" stroke="{I}" stroke-width="2.5"/><path d="M42 32 C42 27 58 27 58 32 L59 42 L41 42 Z" fill="{B}"/><circle cx="47" cy="34" r="1.8" fill="{I}"/><circle cx="53" cy="34" r="1.8" fill="{I}"/>'),
    "honey_jar":      ("common",   f'<rect x="34" y="38" width="32" height="36" rx="8" fill="{T["families"]["sweet"]["c"]}"/><rect x="32" y="30" width="36" height="10" rx="5" fill="{T["families"]["sweet"]["d"]}"/><path d="M40 52 C46 56 54 56 60 52 L60 66 C54 70 46 70 40 66 Z" fill="{T["cream"]}" opacity=".35"/>'),
    "stock_pot":      ("common",   f'<rect x="30" y="44" width="40" height="28" rx="6" fill="{I}"/><rect x="28" y="40" width="44" height="7" rx="3.5" fill="#3A3350"/><circle cx="50" cy="36" r="4" fill="{B}"/><rect x="22" y="50" width="8" height="6" rx="3" fill="{I}"/><rect x="70" y="50" width="8" height="6" rx="3" fill="{I}"/>'),
    "street_cart":    ("common",   f'<rect x="28" y="42" width="44" height="22" rx="4" fill="{T["families"]["spicy"]["c"]}"/><path d="M24 42 L76 42 L72 32 L28 32 Z" fill="{B}"/><circle cx="38" cy="70" r="7" fill="{I}"/><circle cx="62" cy="70" r="7" fill="{I}"/><rect x="40" y="48" width="20" height="4" rx="2" fill="{T["cream"]}" opacity=".6"/>'),
    "big_spoon":      ("common",   f'<ellipse cx="50" cy="36" rx="14" ry="17" fill="{B}"/><ellipse cx="50" cy="34" rx="8" ry="10" fill="{T["brassDark"]}"/><rect x="46" y="50" width="8" height="30" rx="4" fill="{B}"/>'),
    "rice_cooker":    ("common",   f'<rect x="30" y="40" width="40" height="32" rx="10" fill="{P}" stroke="{I}" stroke-width="2.5"/><path d="M30 50 L70 50" stroke="{I}" stroke-width="2.5"/><circle cx="50" cy="60" r="4" fill="{T["families"]["spicy"]["c"]}"/><rect x="40" y="32" width="20" height="8" rx="4" fill="{I}"/>'),
    "tandoor":        ("uncommon", f'<path d="M32 34 C32 28 68 28 68 34 L64 68 C64 76 36 76 36 68 Z" fill="#B0653A"/><path d="M36 36 L64 36" stroke="#8A4A26" stroke-width="3"/><ellipse cx="50" cy="58" rx="10" ry="12" fill="{I}"/><path d="M46 60 C46 54 50 52 50 48 C52 52 56 54 54 60 C53 63 47 63 46 60 Z" fill="{T["families"]["spicy"]["c"]}"/>'),
    "pressure_cooker":("uncommon", f'<rect x="28" y="44" width="44" height="28" rx="9" fill="#C8CAD4"/><rect x="26" y="38" width="48" height="8" rx="4" fill="#9A9DAD"/><rect x="46" y="28" width="8" height="10" rx="3" fill="{I}"/><rect x="72" y="48" width="10" height="6" rx="3" fill="{I}"/><path d="M50 24 C48 20 52 18 50 14" stroke="{T["textLo"]}" stroke-width="3" fill="none" stroke-linecap="round"/>'),
    "wok":            ("uncommon", f'<path d="M24 46 L76 46 C74 62 64 70 50 70 C36 70 26 62 24 46 Z" fill="{I}"/><path d="M24 46 L76 46" stroke="#3A3350" stroke-width="4"/><rect x="12" y="43" width="12" height="6" rx="3" fill="{I}"/><rect x="76" y="43" width="12" height="6" rx="3" fill="{I}"/>'),
    "chai_stall":     ("uncommon", f'<path d="M34 40 L58 40 L56 64 C56 68 36 68 36 64 Z" fill="{B}"/><path d="M58 44 C66 44 66 56 58 56" stroke="{B}" stroke-width="4" fill="none"/><rect x="38" y="32" width="16" height="8" rx="3" fill="{T["brassDark"]}"/><path d="M64 66 L78 66 L76 76 L66 76 Z" fill="{P}" stroke="{I}" stroke-width="2"/>'),
    "bamboo_steamer": ("uncommon", f'<rect x="28" y="34" width="44" height="16" rx="8" fill="#D9B98A"/><rect x="28" y="54" width="44" height="16" rx="8" fill="#C4A271"/><g stroke="#A6875A" stroke-width="2.5"><line x1="36" y1="34" x2="36" y2="50"/><line x1="50" y1="34" x2="50" y2="50"/><line x1="64" y1="34" x2="64" y2="50"/><line x1="43" y1="54" x2="43" y2="70"/><line x1="57" y1="54" x2="57" y2="70"/></g>'),
    "butchers_block": ("uncommon", f'<rect x="26" y="52" width="48" height="16" rx="4" fill="#B0653A"/><path d="M26 58 L74 58" stroke="#8A4A26" stroke-width="2.5"/><path d="M40 26 L62 26 C68 26 70 32 66 36 L48 44 L40 44 Z" fill="#C8CAD4"/><rect x="34" y="30" width="8" height="14" rx="3" fill="{I}"/>'),
    "ice_box":        ("uncommon", f'<rect x="30" y="34" width="40" height="40" rx="8" fill="{T["families"]["salty"]["c"]}"/><path d="M50 42 L50 66 M40 48 L60 60 M60 48 L40 60" stroke="{T["cream"]}" stroke-width="4" stroke-linecap="round"/>'),
    "griddle":        ("uncommon", f'<rect x="26" y="52" width="48" height="12" rx="6" fill="{I}"/><g stroke="{T["families"]["spicy"]["c"]}" stroke-width="4" fill="none" stroke-linecap="round"><path d="M36 44 C34 38 38 36 36 30"/><path d="M50 44 C48 38 52 36 50 30"/><path d="M64 44 C62 38 66 36 64 30"/></g>'),
    "clay_handi":     ("rare",     f'<path d="M30 48 C30 38 40 32 50 32 C60 32 70 38 70 48 C70 62 62 72 50 72 C38 72 30 62 30 48 Z" fill="#B0653A"/><ellipse cx="50" cy="34" rx="14" ry="5" fill="#8A4A26"/><circle cx="50" cy="26" r="5" fill="#8A4A26"/><path d="M36 46 C38 56 44 62 50 64" stroke="{T["cream"]}" stroke-width="3.5" fill="none" opacity=".4" stroke-linecap="round"/>'),
    "grandmothers_ladle": ("rare", f'<ellipse cx="42" cy="58" rx="15" ry="12" fill="{B}"/><ellipse cx="42" cy="55" rx="9" ry="6" fill="{T["brassDark"]}"/><path d="M54 50 C64 40 70 34 76 26" stroke="{B}" stroke-width="7" fill="none" stroke-linecap="round"/><path d="M46 36 C46 32 50 30 52 33 C54 30 58 32 58 36 C58 40 52 43 52 43 C52 43 46 40 46 36 Z" fill="{T["families"]["spicy"]["c"]}"/>'),
    "golden_sieve":   ("rare",     f'<circle cx="50" cy="52" r="22" fill="none" stroke="{B}" stroke-width="5"/><g stroke="{B}" stroke-width="2" opacity=".8"><line x1="34" y1="44" x2="66" y2="44"/><line x1="30" y1="52" x2="70" y2="52"/><line x1="34" y1="60" x2="66" y2="60"/><line x1="42" y1="32" x2="42" y2="72"/><line x1="50" y1="30" x2="50" y2="74"/><line x1="58" y1="32" x2="58" y2="72"/></g>'),
    "emperors_wok":   ("rare",     f'<path d="M26 50 L74 50 C72 64 62 71 50 71 C38 71 28 64 26 50 Z" fill="{I}"/><rect x="14" y="47" width="12" height="6" rx="3" fill="{I}"/><rect x="74" y="47" width="12" height="6" rx="3" fill="{I}"/><path d="M36 40 L42 30 L50 38 L58 30 L64 40 Z" fill="{B}"/><circle cx="42" cy="30" r="2.5" fill="{B}"/><circle cx="58" cy="30" r="2.5" fill="{B}"/>'),
    }

def utensil_badge_svg(name):
    rarity, art = utensil_defs()[name]
    ring = T["rarity"][rarity]
    inner = (f'<circle cx="50" cy="52" r="44" fill="{T["surface2"]}"/>'
             f'{sunburst(50, 52, 26, 44, 10, ring, 0.12)}'
             f'{art}'
             f'<circle cx="50" cy="52" r="44" fill="none" stroke="{ring}" stroke-width="3.5"/>')
    return svg(104, 104, inner, vb="0 0 100 104")

# ---------------------------------------------------------------- CRITICS
def critic_svgs():
    P, I, B = T["parchment"], T["ink"], T["brass"]
    base = lambda extra: svg(120, 120, (
        f'<circle cx="60" cy="60" r="56" fill="{P}"/>'
        f'<circle cx="60" cy="60" r="56" fill="none" stroke="{B}" stroke-width="4"/>'
        f'{sunburst(60, 60, 34, 54, 14, B, 0.15)}'
        f'<path d="M28 96 C30 76 44 68 60 68 C76 68 90 76 92 96 Z" fill="{I}"/>'
        f'<circle cx="60" cy="46" r="20" fill="{I}"/>' + extra))
    minimalist = base(
        f'<circle cx="68" cy="44" r="9" fill="none" stroke="{B}" stroke-width="3"/>'
        f'<line x1="74" y1="51" x2="80" y2="60" stroke="{B}" stroke-width="3"/>'
        f'<path d="M52 82 L60 76 L68 82 L60 88 Z" fill="{B}"/>')
    traditionalist = base(
        f'<path d="M40 34 C40 24 80 24 80 34 L78 40 L42 40 Z" fill="{T["families"]["spicy"]["d"]}"/>'
        f'<path d="M44 56 C50 64 70 64 76 56 C72 68 48 68 44 56 Z" fill="#C8CAD4"/>')
    return {"minimalist": minimalist, "traditionalist": traditionalist}

# ---------------------------------------------------------------- BACKDROPS (poster vistas)
def backdrop(city):
    W, H = 540, 260
    if city == "kochi":
        sky1, sky2, sun, sil = "#2B2144", "#7A3B52", "#E8A020", "#171426"
        art = (f'<circle cx="150" cy="150" r="62" fill="{sun}"/>'
               # chinese fishing nets
               f'<g stroke="{sil}" stroke-width="6" stroke-linecap="round">'
               f'<line x1="330" y1="210" x2="410" y2="90"/><line x1="410" y1="90" x2="470" y2="140"/>'
               f'</g>'
               
               f'<path d="M74 210 C70 186 72 166 80 148 L90 150 C84 168 82 188 84 210 Z" fill="{sil}"/>'
               f'<g fill="{sil}">'
               f'<ellipse cx="66" cy="138" rx="26" ry="8" transform="rotate(-32 66 138)"/>'
               f'<ellipse cx="104" cy="136" rx="26" ry="8" transform="rotate(26 104 136)"/>'
               f'<ellipse cx="62" cy="150" rx="22" ry="7" transform="rotate(-64 62 150)"/>'
               f'<ellipse cx="110" cy="148" rx="22" ry="7" transform="rotate(58 110 148)"/>'
               f'<ellipse cx="86" cy="128" rx="8" ry="22"/></g>'
               f'<path d="M410 90 L430 150 L466 128 Z" fill="none" stroke="{sil}" stroke-width="4"/>'
               f'<g stroke="{sil}" stroke-width="2" opacity=".85"><line x1="418" y1="112" x2="448" y2="138"/><line x1="424" y1="130" x2="452" y2="122"/></g>')
    elif city == "tokyo":
        sky1, sky2, sun, sil = "#1E1B38", "#5A2B4E", "#E23B22", "#171426"
        art = (f'<circle cx="390" cy="120" r="56" fill="{sun}"/>'
               f'<path d="M180 210 L260 96 L292 140 L308 128 L340 210 Z" fill="#3A3355"/>'
               f'<path d="M252 108 L260 96 L268 108 L262 116 L258 116 Z" fill="{T["cream"]}" opacity=".9"/>'
               # torii gate
               f'<g fill="{sil}"><rect x="70" y="134" width="10" height="76"/><rect x="130" y="134" width="10" height="76"/>'
               f'<path d="M54 122 L156 122 L150 134 L60 134 Z"/><rect x="66" y="144" width="78" height="8" rx="3"/><rect x="100" y="134" width="10" height="10"/></g>')
    else:  # naples
        sky1, sky2, sun, sil = "#241F44", "#8A4A3A", "#D9A441", "#171426"
        art = (f'<circle cx="130" cy="120" r="52" fill="{sun}"/>'
               f'<path d="M250 210 L330 110 L352 134 L376 104 L460 210 Z" fill="#3A3355"/>'
               f'<path d="M330 110 C336 100 346 100 352 108 L352 134 Z" fill="{sun}" opacity=".55"/>'
               f'<g fill="{sil}"><path d="M92 210 L92 176 C92 160 124 160 124 176 L124 210 Z"/>'
               f'<circle cx="108" cy="162" r="14"/><rect x="105" y="142" width="6" height="12" rx="3"/>'
               f'<path d="M170 210 C164 186 164 166 170 150 C176 166 176 186 170 210 Z"/></g>')
    inner = (f'<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'
             f'<stop offset="0" stop-color="{sky1}"/><stop offset="1" stop-color="{sky2}"/></linearGradient>'
             f'<linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">'
             f'<stop offset="0" stop-color="{T["bg"]}" stop-opacity="0"/><stop offset="1" stop-color="{T["bg"]}"/></linearGradient></defs>'
             f'<rect width="{W}" height="{H}" fill="url(#g)"/>'
             + art +
             f'<rect y="130" width="{W}" height="130" fill="url(#fade)"/>')
    return svg(W, H, inner)

# ---------------------------------------------------------------- BRAND
def logo_svg():
    return svg(420, 120, (
        f'{sunburst(60, 60, 22, 52, 12, T["brass"], 0.3)}'
        f'<circle cx="60" cy="60" r="20" fill="{T["brass"]}"/>'
        f'<g fill="{T["bg"]}">' + "".join(
            f'<ellipse cx="60" cy="46" rx="5" ry="12" transform="rotate({a} 60 60)"/>'
            for a in range(0, 360, 60)) + '</g>'
        f'<circle cx="60" cy="60" r="4.5" fill="{T["bg"]}"/>'
        f'<path d="M108 60 C150 30 200 92 250 60 C300 30 350 80 396 56" stroke="{T["brass"]}" '
        f'stroke-width="3" stroke-dasharray="1 9" fill="none" stroke-linecap="round"/>'
        f'<text x="108" y="52" font-family="Fraunces, Georgia, serif" font-size="42" font-weight="700" '
        f'fill="{T["textHi"]}" letter-spacing="2">SPICE ROUTE</text>'
        f'<text x="110" y="96" font-family="Inter, sans-serif" font-size="13" letter-spacing="6" '
        f'fill="{T["textLo"]}">A  DELICIOUS  ROGUELIKE</text>'))

def app_icon_svg():
    F = T["families"]["spicy"]["c"]
    chili = icon_defs()["red_chili"].replace("{F}", F).replace("{D}", T["families"]["spicy"]["d"])
    return svg(240, 240, (
        f'<rect width="240" height="240" rx="54" fill="{T["bg"]}"/>'
        f'{sunburst(120, 120, 52, 116, 16, T["brass"], 0.22)}'
        f'<circle cx="120" cy="120" r="78" fill="{T["parchment"]}"/>'
        f'<circle cx="120" cy="120" r="78" fill="none" stroke="{T["brass"]}" stroke-width="7"/>'
        f'<g transform="translate(54,52) scale(1.28)">{chili}</g>'))

# ---------------------------------------------------------------- PREVIEW PAGE
def mock_card_html(fam, rank, icon, name, small=False):
    s = card_svg(fam, rank, icon, name)
    cls = "card small" if small else "card"
    return f'<div class="{cls}">{s}</div>'

def build_preview(cards, utensils, critics, backs):
    fam_chip = "".join(
        f'<span class="chip" style="background:{v["c"]}">{v["name"]}</span>'
        for v in T["families"].values())
    utensil_grid = "".join(
        f'<figure>{svgstr}<figcaption>{n.replace("_", " ").title()}</figcaption></figure>'
        for n, svgstr in utensils.items())
    critic_grid = "".join(
        f'<figure>{s}<figcaption>The {n.title()}</figcaption></figure>' for n, s in critics.items())
    backs_html = "".join(f'<div class="backdrop"><div class="cap">{c.title()}</div>{s}</div>'
                         for c, s in backs.items())
    hand = (mock_card_html("sweet", 5, "palm_sugar", "Palm Sugar", True) +
            mock_card_html("sweet", 6, "maple", "Maple", True) +
            mock_card_html("spicy", 7, "birds_eye_chili", "Bird's Eye Chili", True) +
            mock_card_html("spicy", 8, "scotch_bonnet", "Scotch Bonnet", True) +
            mock_card_html("spicy", 6, "red_chili", "Red Chili", True) +
            mock_card_html("spicy", 4, "mustard_seed", "Mustard Seed", True) +
            mock_card_html("umami", 5, "dashi", "Dashi", True) +
            mock_card_html("sour", 10, "fermented_lime", "Fermented Lime", True))
    gallery = "".join(mock_card_html(f, r, i, n) for f, r, i, n in cards)

    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Project Tadka — Visual Identity Preview</title>
<link href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,600;9..144,700&family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
<style>
:root {{ --bg:{T['bg']}; --surface:{T['surface']}; --surface2:{T['surface2']};
  --parchment:{T['parchment']}; --ink:{T['ink']}; --brass:{T['brass']};
  --hi:{T['textHi']}; --lo:{T['textLo']}; }}
* {{ box-sizing:border-box; margin:0; }}
body {{ background:var(--bg); color:var(--hi); font-family:Inter,system-ui,sans-serif;
  padding:20px 16px 80px; max-width:760px; margin:0 auto; }}
h1,h2 {{ font-family:Fraunces,Georgia,serif; }}
h1 {{ font-size:30px; }} h2 {{ font-size:21px; margin:44px 0 6px; color:var(--brass); }}
.sub {{ color:var(--lo); font-size:14px; margin:6px 0 18px; line-height:1.5; }}
.chip {{ display:inline-block; color:#fff; font-size:11px; font-weight:700;
  letter-spacing:1px; padding:4px 10px; border-radius:99px; margin:0 6px 6px 0; }}
.card svg {{ width:150px; height:auto; filter:drop-shadow(0 6px 14px rgba(0,0,0,.45)); }}
.card.small svg {{ width:76px; }}
.cardrow {{ display:flex; flex-wrap:wrap; gap:12px; }}
.handgrid {{ display:grid; grid-template-columns:repeat(4,1fr); gap:8px; justify-items:center; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(96px,1fr)); gap:12px; }}
figure {{ background:var(--surface); border-radius:14px; padding:10px 6px; text-align:center; }}
figure svg {{ width:64px; height:auto; }}
figcaption {{ font-size:10.5px; color:var(--lo); margin-top:6px; }}
.phone {{ background:var(--surface); border:1px solid #352E52; border-radius:22px;
  padding:14px; box-shadow:0 12px 40px rgba(0,0,0,.5); }}
.hdr {{ display:flex; justify-content:space-between; align-items:baseline; }}
.city {{ font-family:Fraunces,serif; font-size:20px; font-weight:700; }}
.score {{ font-family:Fraunces,serif; font-size:38px; font-weight:700; color:var(--brass); }}
.target {{ text-align:right; color:var(--lo); font-size:12px; }} 
.target b {{ color:var(--hi); font-size:16px; font-family:Fraunces,serif; }}
.meter {{ height:6px; background:#352E52; border-radius:99px; margin:8px 0 12px; overflow:hidden; }}
.meter i {{ display:block; height:100%; width:34%; background:linear-gradient(90deg,var(--brass),#F0C36A); border-radius:99px; }}
.pal {{ font-size:12.5px; margin:3px 0; }} .pal.g {{ color:{T['good']}; }} .pal.r {{ color:{T['danger']}; }}
.rack {{ display:flex; gap:8px; margin:12px 0; }}
.rack figure {{ flex:1; padding:8px 2px; background:var(--surface2); }}
.rack svg {{ width:44px; }}
.btns {{ display:flex; gap:10px; margin-top:14px; }}
.btn {{ flex:1; text-align:center; font-weight:700; padding:15px 0; border-radius:14px; font-size:15px; }}
.btn.cook {{ background:linear-gradient(180deg,#F0C36A,var(--brass)); color:var(--ink);
  box-shadow:0 4px 0 {T['brassDark']}; }}
.btn.swap {{ border:2px solid #443C68; color:var(--hi); }}
.btn small {{ display:block; font-weight:600; font-size:10.5px; opacity:.7; }}
.backdrop {{ position:relative; border-radius:16px; overflow:hidden; margin-bottom:14px; }}
.backdrop svg {{ display:block; width:100%; height:auto; }}
.cap {{ position:absolute; left:14px; bottom:10px; font-family:Fraunces,serif;
  font-size:19px; font-weight:700; z-index:2; }}
.tok {{ display:flex; flex-wrap:wrap; gap:10px; }}
.tok div {{ width:104px; border-radius:12px; overflow:hidden; background:var(--surface); font-size:10.5px; }}
.tok i {{ display:block; height:44px; }} .tok span {{ display:block; padding:6px 8px; color:var(--lo); }}
.logo svg {{ width:100%; max-width:420px; height:auto; }}
.appicon svg {{ width:110px; height:auto; border-radius:24px; box-shadow:0 10px 30px rgba(0,0,0,.5); }}
@media (prefers-reduced-motion:no-preference) {{
  .spin {{ animation:spin 40s linear infinite; transform-origin:center; }}
  @keyframes spin {{ to {{ transform:rotate(360deg); }} }} }}
</style></head><body>
<div class="logo">{logo_svg()}</div>
<p class="sub">Visual identity preview — "Midnight Bazaar." Vintage spice-trade labels on a
night-market sky: parchment cards, brass, one sunburst signature. Judge it in one scroll.</p>
{fam_chip}

<h2>The game screen, reskinned</h2>
<p class="sub">Your exact Kochi critic round from today, wearing the new identity.</p>
<div class="phone">
  <div class="hdr"><span class="city">Kochi 🇮🇳</span>
    <span class="target">THE FOOD CRITIC · RUN 1·3<br><b>target 2,000</b></span></div>
  <div class="score">0</div>
  <div class="meter"><i style="width:0%"></i></div>
  <div class="pal g">🍽 Palate — Sour ingredients give +50% intensity as flavor</div>
  <div class="pal r">👤 The Minimalist — dishes may use at most 3 ingredients</div>
  <div class="rack">
    <figure>{utensil_badge_svg("emperors_wok")}<figcaption>Emperor's Wok</figcaption></figure>
    <figure>{utensil_badge_svg("iron_tawa")}<figcaption>Iron Tawa</figcaption></figure>
    <figure style="opacity:.35"><figcaption style="padding:18px 0">empty</figcaption></figure>
    <figure style="opacity:.35"><figcaption style="padding:18px 0">empty</figcaption></figure>
    <figure style="opacity:.35"><figcaption style="padding:18px 0">empty</figcaption></figure>
  </div>
  <div class="handgrid">{hand}</div>
  <div class="btns"><div class="btn cook">COOK<small>4 left</small></div>
    <div class="btn swap">SWAP<small>3 left</small></div></div>
</div>

<h2>Ingredient cards</h2>
<p class="sub">The signature asset: parchment spice-label, scalloped family band, sunburst
behind every ingredient, Fraunces numerals. One per family shown large.</p>
<div class="cardrow">{gallery}</div>

<h2>Utensils — all 20, rarity-ringed</h2>
<p class="sub">Grey ring common · green uncommon · brass rare.</p>
<div class="grid">{utensil_grid}</div>

<h2>Food critics</h2>
<div class="grid" style="grid-template-columns:repeat(auto-fill,minmax(120px,1fr))">{critic_grid}</div>

<h2>City backdrops</h2>
<p class="sub">Poster vistas that fade into the UI. Sun color shifts per region.</p>
{backs_html}

<h2>App icon</h2>
<div class="appicon">{app_icon_svg()}</div>

<h2>Palette tokens</h2>
<div class="tok">
  <div><i style="background:{T['bg']}"></i><span>Midnight {T['bg']}</span></div>
  <div><i style="background:{T['surface']}"></i><span>Awning {T['surface']}</span></div>
  <div><i style="background:{T['parchment']}"></i><span>Parchment {T['parchment']}</span></div>
  <div><i style="background:{T['brass']}"></i><span>Brass {T['brass']}</span></div>
  <div><i style="background:{T['families']['spicy']['c']}"></i><span>Spicy</span></div>
  <div><i style="background:{T['families']['sweet']['c']}"></i><span>Sweet</span></div>
  <div><i style="background:{T['families']['sour']['c']}"></i><span>Sour</span></div>
  <div><i style="background:{T['families']['salty']['c']}"></i><span>Salty</span></div>
  <div><i style="background:{T['families']['umami']['c']}"></i><span>Umami</span></div>
</div>
</body></html>"""

# ---------------------------------------------------------------- MAIN
def main():
    ensure_dirs()
    write("ui/tokens.json", json.dumps(T, indent=2))

    # ingredient icons (plain + sunburst-boxed)
    for name in icon_defs():
        write(f"ingredients/{name}.svg", ingredient_icon_svg(name))
        write(f"ingredients/{name}_sunburst.svg", ingredient_icon_svg(name, boxed=True))

    # example full cards, one per family + the run-1 hand
    card_specs = [
        ("spicy", 7, "birds_eye_chili", "Bird's Eye Chili"),
        ("sweet", 6, "maple", "Maple"),
        ("sour", 10, "fermented_lime", "Fermented Lime"),
        ("salty", 3, "salt_crystal", "Rock Salt"),
        ("umami", 5, "dashi", "Dashi"),
    ]
    for fam, rank, icon, name in card_specs:
        write(f"cards/{fam}_{rank}_{icon}.svg", card_svg(fam, rank, icon, name))

    utensils = {n: utensil_badge_svg(n) for n in utensil_defs()}
    for n, s in utensils.items():
        write(f"utensils/{n}.svg", s)

    critics = critic_svgs()
    for n, s in critics.items():
        write(f"critics/{n}.svg", s)

    backs = {c: backdrop(c) for c in ["kochi", "tokyo", "naples"]}
    for c, s in backs.items():
        write(f"backdrops/{c}.svg", s)

    write("brand/logo.svg", logo_svg())
    write("brand/app_icon.svg", app_icon_svg())

    write("preview.html", build_preview(card_specs, utensils, critics, backs))
    print("Asset pack written to", OUT)
    total = sum(len(files) for _, _, files in os.walk(OUT))
    print("Files:", total)

if __name__ == "__main__":
    main()
