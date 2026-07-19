# SPICE ROUTE — Game Concept Document v1.1

*Dev code name: **Project Tadka** (repo: `tadka`). Working title "Spice Route"; final store name TBD after trademark/ASO check. A premium roguelike deckbuilder for iOS & Android.*

---

## 1. Elevator Pitch

You are a traveling cook journeying the world's great food routes. In each city — Kochi, Bangkok, Istanbul, Naples, Oaxaca — you set up a pop-up kitchen and must impress ever-more-demanding diners by cooking dishes from your pantry of ingredient cards. Poker-style ingredient combinations become recipes named after that city's iconic dishes; legendary utensils and street vendors multiply your scores into absurd numbers. Fail a dinner rush and the run ends — but you unlock new content and immediately want to go again.

- **Genre:** Roguelike deckbuilder (score-attack), single-player, offline
- **Platform:** iOS + Android, portrait-first, one-hand play
- **Price:** Premium — $4.99 US / ₹399–499 India. No ads, no IAP, ever (this is a marketing feature, not just ethics)
- **Session length:** A full run is 30–45 min; naturally pausable every 2–3 min
- **Comparables:** Balatro (loop + monetization model), Slice & Dice (mobile-first premium execution), Luck be a Landlord (simple art, deep systems)
- **One-line positioning:** "Balatro, but you're cooking — and every combo is a dish you wish you could eat."

---

## 2. Theme — DECIDED: Global Food (Option A, world-cuisine version)

**Yeshu's direction (confirmed):** food theme, expanded from Indian street food to **the world's iconic dishes** — every region, country, and culture represented, so players everywhere see their own food in the game.

### Option A — Spice Route: World Edition ✅ CHOSEN
- **Why it wins on marketing:** Food content is one of the highest-performing categories on TikTok/Reels/Shorts, and the global framing means every regional food community (Italian, Mexican, Japanese, Thai, Middle Eastern...) is a marketing channel. A 15-second clip of a "48,000-point Ramen combo" or "Royal Biryani" is instantly legible to non-gamers.
- **Why it wins on reach:** localization becomes a growth lever — Japanese players seeing ramen and dashi done right, Mexican players seeing mole and chipotle, converts far better than a single-culture theme.
- **Why it wins on ratings:** Balatro was hit with 18+ ratings in several regions over simulated-gambling imagery, which hurt its store placement. A food theme has zero gambling optics — we get 4+/Everyone ratings and full featuring eligibility.
- **Authenticity guardrail:** each region's dishes, ingredients, and naming must be researched carefully (and ideally sanity-checked by someone from that culture) — celebration, never caricature. India remains our home-base culture and the route's starting point.

### Archived alternatives (for the record)
**Option B — Navagraha (Vedic cosmic):** original but niche-ier visuals, crowded mystic aesthetic. **Option C — Alchemist's Ledger:** safe but generic. Both rejected in favor of A.

### 2.1 The signature global mechanic: Regional Dish Naming
The same card pattern earns a **different iconic dish name depending on the city you're in** — pure data, zero mechanical cost, maximum cultural connection:

| Pattern | Kochi 🇮🇳 | Naples 🇮🇹 | Tokyo 🇯🇵 | Oaxaca 🇲🇽 | Istanbul 🇹🇷 |
|---|---|---|---|---|---|
| Pair | Chaat | Bruschetta | Onigiri | Elote | Meze |
| Three of a Kind | Curry | Risotto | Ramen | Tacos al Pastor | Pilav |
| Flush | Signature Thali | Margherita | Omakase | Mole Negro | Testi Kebab |
| Straight Flush | Royal Biryani | Nonna's Feast | Kaiseki | Fiesta Grande | Sultan's Table |

Regional **prized ingredients** follow the same logic: Saffron (Iran), Truffle (Italy), Wasabi (Japan), Chipotle (Mexico), Za'atar (Levant), Kimchi (Korea). The five flavor families (Spicy/Sweet/Sour/Salty/Umami) are literally the universal human tastes — they need no localization at all.

---

## 3. How the Game Plays (Core Loop)

### 3.1 The Run Structure
A run = a journey through **8 cities** drawn from a pool of 12 world food capitals (e.g., Kochi → Bangkok → Tokyo → Istanbul → Marrakech → Naples → Oaxaca → The Grand Bazaar). Each city has **3 dinner services**:

1. **Lunch Rush** (small score target)
2. **Dinner Rush** (bigger target)
3. **The Food Critic** (boss — big target + a rule-twisting demand)

Beat all three → travel onward. Miss a target → run over. Between services you visit the **Bazaar** (shop) to buy utensils, spice blends, and pantry upgrades with coins earned from cooking.

### 3.2 The Turn Loop (the minute-to-minute)
- Your **pantry** is a deck of 52 ingredient cards: **5 flavor families** (suits) — Spicy 🌶️, Sweet 🍯, Sour 🍋, Salty 🧂, Umami 🍄 — each with **intensity ranks 1–10** (plus face-card-tier "prized ingredients").
- Each turn you hold **8 ingredients**, and choose up to **5 to cook as one dish**. You get **4 dishes** and **3 pantry swaps (discards)** per service.
- The combination you play determines the **recipe**:

| Card pattern | Recipe name | Base Flavor × Heat |
|---|---|---|
| High card | Street Snack | 5 × 1 |
| Pair | Chaat | 10 × 2 |
| Two Pair | Combo Plate | 20 × 2 |
| Three of a Kind | Curry | 30 × 3 |
| Straight (run of intensities) | Thali | 30 × 4 |
| Flush (one flavor family) | Signature Dish | 35 × 4 |
| Full House | Feast | 40 × 4 |
| Four of a Kind | Royal Curry | 60 × 7 |
| Straight Flush | Masterpiece | 100 × 8 |

- **Score = (Base Flavor + ingredient intensities + bonuses) × (Heat + multipliers).** Every played ingredient pops, counts up, and triggers utensils — the Balatro-style dopamine cascade is the core of game feel.

### 3.3 Utensils & Vendors (the Joker system — where depth lives)
You can equip **5 utensils/vendors**. They are permanent passive modifiers, and their interactions are the entire strategy game. Launch target: **90–110 utensils** across rarities. Examples:

- **Common — Iron Tawa:** +30 Flavor if the dish has 3+ ingredients
- **Common — Mint Garnish:** +4 Heat if the dish contains a Sour ingredient
- **Uncommon — Tandoor:** ×1.5 Heat if every ingredient is Spicy
- **Uncommon — Pressure Cooker:** retrigger the highest-intensity ingredient
- **Uncommon — Chai Stall:** earn 1 coin every time you play a Pair
- **Rare — Grandmother's Ladle:** copies the ability of the utensil to its right
- **Rare — Clay Handi:** the final dish of each service scores ×3
- **Legendary — The Golden Thali:** all Straights count as Straight Flushes

### 3.4 Consumables & Upgrades
- **Spice Blends** (tarot-analog, single-use): transform ingredients — "Chili Oil: convert 2 cards to Spicy," "Fermentation: +3 intensity to a card," "Sun-Dry: duplicate a card"
- **Festival Cards** (planet-analog): permanently level up one recipe type for this run ("Diwali: Feasts gain +15 Flavor, +2 Heat")
- **Prized Ingredients:** cards can gain seals/foils — "Saffron-laced" (+50 Flavor), "Ghee-roasted" (retriggers), "Preserved" (survives shuffles)

### 3.5 City Palates (our original twist #1 — cheap, high strategic value)
Every city has a **palate** that modifies scoring for that city's three services: *Kochi loves Sour (+50% Flavor from Sour cards). Jaipur loves Sweet (+2 Heat on dishes with Sweet). Basra distrusts Umami (Umami scores 0).* Palates are visible one city ahead, so builds must adapt route-style — a strategic dimension Balatro doesn't have, and it makes runs feel like a journey.

### 3.6 Food Critics (boss blinds)
Each city's third service adds a critic with a demand, e.g.:
- **The Minimalist:** dishes may use max 3 ingredients
- **The Traditionalist:** debuffs all Sweet ingredients
- **The Rival Chef:** beat the target within 3 dishes
- **The Health Inspector:** your leftmost utensil is disabled

### 3.7 Meta-progression (the "one more run" engine)
- New utensils, blends, and pantry types unlock by playing (achievement-gated, ~60% locked at first launch)
- **5 pantry decks** (starting-deck variants: "Coastal Pantry — extra Sour," "Royal Kitchen — start with a Legendary but smaller pantry")
- **8 difficulty stakes** after first win
- **Daily Route:** seeded daily challenge, local leaderboard v1, global later

### v1.1 twist reserved: **Monsoon Mode** — ingredients gain freshness that decays; spoiled cards score negative unless preserved. Ships as hard mode post-launch.

---

## 4. Scope — v1.0 Content Targets

| Content | Launch count |
|---|---|
| Utensils/Vendors | 90–110 |
| Spice Blends | 20 |
| Festival Cards | 10 |
| Cities (with palates + art) | 12 in pool, 8 per run |
| Food Critics | 16 |
| Pantry decks | 5 |
| Stakes (difficulties) | 8 |
| Recipe types | 9 (+3 secret) |

All content is **data-driven (JSON)** — Claude Code generates, tunes, and tests content without engine changes.

---

## 5. Art Brief (for hiring the freelance artist)

**Style direction:** Warm flat illustration / gouache "vintage travel poster" — think Monument Valley's color confidence meets Indian matchbox-label art. Saturated spice tones (turmeric, chili red, cardamom green) on deep teal/indigo backgrounds. NOT pixel art, NOT realistic food photography, NOT Balatro's CRT look.

**Asset list (deliverables):**
1. **Ingredient card system** — 1 card frame + 5 flavor-family color schemes + **~40 ingredient icons** (icons combine with frames/colors so we don't need 52 unique paintings)
2. **Utensil/vendor illustrations** — 110 small stylized pieces (400×400). The single biggest item; batch in 3 drops of ~37
3. **City backdrops** — 12 scenes (can be simple layered vistas)
4. **Critic portraits** — 16 characters
5. **UI kit** — buttons, panels, score area, shop, fonts pairing
6. **App icon + store screenshots template + logo**
7. **VFX sprite sheets** — sizzle, steam, spice-burst particles (or artist supplies stills, we animate in-engine)

**Process:** paid style test (2 cards + 1 utensil + 1 backdrop) from 2–3 candidates before committing. Milestone-based contract, source files included, full commercial rights, 2 revision rounds per batch.

**Where to hire:** Behance/ArtStation (search "flat illustration food"), Twitter/X gamedev art community, Polycount, Indian illustration communities (Kulfi Collective-adjacent freelancers).

**Budget estimate:** ₹2.0–3.5L total across 10–12 weeks. Sound: licensed SFX packs + a freelance pass for regional musical motifs (tabla/oud/santoor per region), ₹30–60K.

---

## 6. Tech Architecture (for Claude Code)

- **Engine:** Flutter + Flame. Pure-code workflow (no GUI editor), hot reload for feel iteration, single codebase for iOS/Android.
- **Structure:** `game_core` (pure Dart, zero Flutter deps: scoring engine, RNG, run state) / `game_ui` (Flame rendering, animation, juice) / `content` (JSON: utensils, blends, critics, palates) / `sim` (headless CLI).
- **Determinism:** seeded RNG throughout → enables daily challenges, replay-from-seed bug reports, and golden-file tests of the scoring engine.
- **Balance simulator (our secret weapon):** headless Dart CLI that plays 100K+ runs per content change with scripted bot policies; outputs win-rate per utensil, score distributions, degenerate-combo detection. Every balance PR includes sim results.
- **Juice checklist (M2):** count-up score ticker with easing, card pop + wobble on trigger, screen shake scaled to Heat, particle bursts per flavor family, haptics on big combos, pitch-rising SFX chain on retriggers.
- **Saves:** local only v1 (no accounts, no backend). Cloud save via platform APIs (iCloud/Play Games) in v1.1.
- **Analytics:** privacy-light (aggregate events only — run length, death city, utensil pick rates) via a minimal self-hosted endpoint or Firebase; needed to balance post-launch.

---

## 7. Three-Month Milestone Plan

**M0 — Graybox Fun Check (Weeks 1–2)**
Playable core loop with text-only cards: pantry, 9 recipes, scoring cascade, 15 placeholder utensils, one 3-service city. *Exit criteria: Yeshu voluntarily plays 5+ runs in one sitting. If the loop isn't fun in graybox, we fix or kill here — cheaply.*

**M1 — Full Run + Artist Hired (Weeks 3–6)**
8-city run structure, bazaar/shop economy, 40 utensils, 12 blends, 6 critics, palate system, save/load. Balance simulator v1 running. Artist style tests done, contract signed, first art batch commissioned. *Exit criteria: full run completable; sim shows no dominant strategy >60% pick rate; art direction locked.*

**M2 — Art, Juice & Content (Weeks 7–10)**
Art integration as batches land. Full juice pass (see checklist). Sound pass. Content to ~90 utensils, 16 critics, unlock/meta-progression system, tutorial, Daily Route. *Exit criteria: a stranger can learn the game from the tutorial alone; the "big combo" moment feels clip-worthy.*

**M3 — Beta, Store & Launch Prep (Weeks 11–13)**
Closed beta via TestFlight + Play Internal (target 50–100 testers from Reddit/Discord). Balance from real data. Store pages, 30-sec trailer, 20 short-form clips banked, press/streamer kit, localization pass (EN first; HI/ES/PT/JA in v1.1). *Exit criteria: beta D1 retention >40%, median session >20 min, crash-free >99.5%.*

**Parallel marketing track (starts M1, ~3 hrs/week):** 2 devlog clips per week (build in public), collect wishlist-equivalent emails via a simple landing page, build a list of 100 deckbuilder streamers/YouTubers (the people who made Balatro), post progress in r/roguelikedeckbuilders and Indian gamedev communities.

---

## 8. Monetization & Launch Strategy

- **Premium $4.99 / ₹399–499.** No ads/IAP — say it loudly on the store page; it converts.
- **Launch sequencing:** iOS + Android simultaneously; launch-week 20% discount; press embargo timed with 20–30 streamer keys sent 2 weeks early.
- **Revenue scenarios (90 days):** Base: 5–10K units ≈ ₹12–30L gross. Good: 25K units. Balatro-tier virality is a lottery ticket — plan costs against the base case.
- **Later:** paid DLC route-pack (new region + 30 utensils), Steam port (the deckbuilder audience's home turf — strongly consider for v1.2).

## 9. Long-Term Freshness Roadmap (Years 1–2)

**Core principle: we are NOT a level-treadmill game.** Candy Crush must hand-craft thousands of levels forever because its content is *consumed* — play a level once, it's spent. Our content is *combinatorial* — freshness comes from randomized runs × 110 utensils × palates × critics × decks, so two runs are never alike. Balatro stayed a top seller for years with almost no content updates. Updates for us are accelerants, not life support — and because our content is JSON + Claude Code + the balance simulator, each update costs days, not months.

### Layer 1 — Freshness built into v1.0 (zero ongoing work)
- Procedural runs (infinite variety by design)
- Unlock ladder: ~60% of utensils/decks locked at launch — weeks of discovery
- 8 escalating stakes after first win (the real endgame)
- 5 pantry decks = 5 different opening strategies
- **Daily Route:** same seed for every player each day, compare scores — the #1 "come back tomorrow" hook, costs nothing to run

### Layer 2 — Light live-ops (quarterly, ~1–2 weeks effort each)
- **Utensil drops:** +10–20 new utensils per update (JSON + sim-balanced)
- **Seasonal festivals:** Diwali, Lunar New Year, Ramadan/Eid, Christmas, Día de Muertos — timed modifiers and cosmetic card backs tied to real food culture; each is a marketing moment
- **Monsoon Mode (v1.1):** freshness/spoilage hard mode (already spec'd)
- Weekly mutator challenges ("all Spicy week," "no discards")

### Layer 3 — Expansion content (the global theme pays off here)
- **New Route Packs = new world regions:** The Pacific Route (Seoul, Osaka, Bangkok, Manila), The Americas Route (Lima, Mexico City, New Orleans, São Paulo), The Silk Road, African Routes — each adds cities, palates, dishes, prized ingredients, critics. Free updates early (goodwill/press), paid DLC packs later (revenue without breaking the no-IAP promise — DLC ≠ microtransactions)
- **Endless Mode:** post-win infinite scaling for the leaderboard crowd
- **Seed sharing:** send a run seed to a friend — "beat my run" viral loop
- **Combo replay export:** one-tap shareable clip of your biggest dish — players become the marketing engine

### Layer 4 — Platform & feature growth (months 6–18)
- Global Daily Route leaderboards, cloud save/cross-device
- **Steam/PC port** — the deckbuilder genre's home turf and likely a revenue event bigger than mobile launch
- Localization waves (JA/KO/ES/PT/DE) timed with matching route packs
- Community utensil design votes (engagement + free ideas)
- If it works: Spice Route 2 or a second systems game reusing the whole engine



## 10. Risks & Honest Mitigations

1. **"Balatro clone" criticism** — inevitable baseline; mitigated by palate/journey system, food identity, and Monsoon Mode. Lean into "inspired by" openly.
2. **Premium mobile is hit-driven** (Slay the Spire mobile did modest numbers) — mitigated by tiny fixed costs, streamer-first plan, and Steam port option.
3. **Art timeline slips** — mitigated by icon+frame card system (cuts asset count ~60%) and batch contracts.
4. **Balance degeneracy at 100+ utensils** — mitigated by the simulator; this is our structural advantage over human-only studios.
5. **Discoverability** — the real boss fight. Marketing track is not optional; it's a third of the project.

---

*Next actions: (1) Yeshu confirms theme, (2) M0 build starts, (3) I draft the artist job post + style-test brief.*
