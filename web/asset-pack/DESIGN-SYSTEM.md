# TADKA Design System — "Midnight Bazaar" v1
*Hand this folder + this file to Opus/Claude Code. Everything needed to skin the beta and generate new assets in-style.*

## Concept
Vintage spice-trade labels come alive on a night-market sky. Parchment cards, brass hardware, one signature motif — the **sunburst** — behind every ingredient, badge, and the app icon. Dark UI stays quiet so cards and scores glow.

## Tokens (`ui/tokens.json`)
Midnight `#171426` bg · Awning `#241F38` panels · Raised `#2E2846` · Parchment `#F5E9D0` card faces · Ink `#2B2438` text-on-parchment · Brass `#D9A441` (+dark `#A87A2B`) coins/CTAs/borders · Text-hi `#F2E8D5` · Text-lo `#9A92B0`.
Families (LOCKED, already in game logic): Spicy `#E23B22`/`#A32612` · Sweet `#E8A020`/`#B0740E` · Sour `#7CB342`/`#557F2B` · Salty `#4A90D9`/`#2F639C` · Umami `#8E5AA8`/`#623A78`. Rarity rings: common `#8A8494`, uncommon `#7CB342`, rare `#D9A441`.

## Type
- **Display: Fraunces** (Google Fonts, weights 600/700) — city names, rank numerals, dish names, the score. The score counter is the biggest type on screen, always Fraunces 700 in Brass.
- **UI: Inter** 400/600/700 — everything else. Labels UPPERCASE, letter-spacing 1–2px, 11–12px.

## Components
- **Card** (`cards/`, 180×252): parchment face, 2px parchDark inner keyline, family band with **scalloped ticket edge**, rank top-left (Fraunces 700, cream), family name top-right (Inter caps), sunburst + icon center, hairline rule + name footer (Fraunces 600, Ink). Selected state: translate up 6px + Brass 3px outer glow.
- **Utensil badge** (`utensils/`, all 20): circular, Raised fill, faint sunburst, flat pictogram, 3.5px rarity ring.
- **Buttons**: COOK = brass vertical gradient (#F0C36A→#D9A441), Ink text, 4px darker bottom edge (physical press feel). SWAP = 2px `#443C68` outline, transparent.
- **Backdrops** (`backdrops/`, 540×260): sit behind the header, bottom 50% fades to Midnight so UI floats over them.
- **Critic medallions** (`critics/`): parchment coin, brass ring, ink bust.

## Icon recipe (for generating NEW ingredients/utensils in-style)
100×100 viewBox · silhouette-first, max 2 tones (family color + its dark) + one cream sparkle/highlight · no strokes on fills except deliberate 2.5–5px rounded linecaps · stems always `#557F2B` · shapes chunky, nothing thinner than 3px · centered mass ≈ (50,52). Add the SVG body to `ICONS`/`UTENSILS` dicts in `generate_assets.py` and re-run — frames, sunbursts, rings, and preview regenerate automatically.

## Motion (juice spec for the build)
- Score count-up: 700ms, easeOutExpo, Fraunces, scale-pop 1.0→1.12→1.0 on land.
- Card trigger: 90ms wobble (±4°) + family-color particle burst (6–10 dots, 400ms, gravity-free fade).
- Big multiplier (×2+): screen shake 3px·120ms, +1px per extra multiple, cap 8px.
- Retrigger: card flashes cream, pitch of tick SFX rises per retrigger.
- Respect `prefers-reduced-motion`: swap all of the above for opacity fades.

## Integration into the current web artifact (instruction for Opus)
1. Import `ui/tokens.json`; replace hard-coded colors with tokens; load Fraunces+Inter.
2. Replace emoji on cards with inline SVG from `ingredients/` (map ingredient id → icon; unknown ingredient → family default: red_chili / honey_pot / lemon / salt_crystal / shiitake).
3. Wrap card layout in the card frame design (band, numeral, footer) — reference `cards/*.svg` for exact geometry, but build it as a styled component, not an <img>, so rank/name stay dynamic.
4. Utensil rack + bazaar offers use `utensils/*.svg` inline with rarity rings.
5. Header shows the current city's backdrop; palate line in `#8FBF6B`, critic line in `#E85A4F`.
6. Implement the Motion spec. 7. App icon/logo from `brand/`.

## What a human artist upgrades later (be honest with ourselves)
Ingredient icons → richer illustrated versions with texture; critic medallions → real character portraits; backdrops → layered parallax scenes; bespoke display lettering for the logo. The tokens, layout, and motion language stay.
