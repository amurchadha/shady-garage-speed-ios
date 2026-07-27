# Backlog — Shady Garage & Speed (iOS)

Mirrors the web repo's BACKLOG.md; items marked iOS are done natively in this port.
Web-only items (browser APIs, CI, docs) are intentionally out of scope.

## Done (iOS)

- [x] #77 First-run tutorial (3 coach marks on first garage visit, persisted flag) — iOS
- [x] #78 Settings screen (gear → sheet: bus sliders, reduced-motion override, difficulty, export, restore, reset) — iOS
- [x] #88 Save backup (`sgs_save_prev` kept before every save; restore from Settings) — iOS
- [x] #37 Volume buses (sfxBus + musicBus split, live sliders) — iOS
- [x] #90 Version display (Info.plist version+build in the menu footer) — iOS
- [x] #1 Second race track + picker (TRACKS table; Figure-8 Ridge peanut-8, pre-race track sheet, scene rebuilt on switch) — iOS
- [x] #2 Fog weather (4th condition: 20%, ~60u visibility, muted palette, headlights on) — iOS
- [x] #13 Per-track best laps (bestLaps{} keyed by track; legacy scalar migrates to classic) — iOS
- [x] #14 Difficulty modes (Chill/Normal/Cutthroat multipliers, Settings select, menu footer) — iOS
- [x] #18 Customer body styles (sedan/hatch/truck mesh variants; trucks lean Big Spender) — iOS
- [x] #61 Golden customer (3% roll, gold paint, all parts tier ≥3, pays ×3, fanfare + ✨ + headline) — iOS
- [x] #65 Elite pity timer (25 customers without a tier-4 sighting forces one) — iOS
- [x] #69 Tiered contracts (Standard ×1/+3d, Rush ×1.6/+1d, Premium ×1.5/+4d & tier 3-4 only; rank badge) — iOS
- [x] #31 Lo-fi garage radio (72bpm Am–F–C–G chiptune, buffer-queue scheduler, musicBus ducked −6dB under SFX; menu/garage/build) — iOS
- [x] #32 Race music loop (128bpm: bass pulse + noise hats + lead arp; starts at GO, stops at finish/forfeit/exit) — iOS
- [x] #21 Chase-cam yaw lag (camera heading low-passed ~4/s; the car visibly rotates in frame when steering, recenters smoothly) — iOS
- [x] #22 Speed lines (24 recycled camera-space streaks radial from screen center above 75% max speed, density ∝ speed; full rate — no COARSE tier on iOS) — iOS
- [x] #23 Impact-scaled camera shake (barrier impulse ∝ pre-penalty impact speed, ~0.3s smooth decay; off-track rumble untouched) — iOS
- [x] #24 Slow-mo finish (0.45× time for 0.9s real over the line + FOV pulse; lap timer keeps true time) — iOS
- [x] #25 Photo mode on results (📷 hides all UI but a tiny hint, camera slowly orbits the parked car; any tap exits) — iOS
- [x] #26 Legend confetti (120 recycled colored quads, gravity + flutter, ~4s over the results scene; web uses 150) — iOS
- [x] #27 Countdown camera pan (high/wide beauty shot of car + gantry swoops into chase over the 3-2-1, every race) — iOS
- [x] #28 Customer entrance variety (normal 50% / reverse-park facing out 25% / fast-and-swing 25% with tire squeak) — iOS
- [x] #29 Owner flinch (hold a Steal button → owner does a suspicious glance-lean, 0.3s) — iOS
- [x] #30 Minimap start pulse (start/finish tick pulses scale/alpha at 1Hz; static under Reduce Motion) — iOS
- [x] #33 Skid sound (bandpass noise loop, gain ∝ lateral slip; same slip condition as skid marks) — iOS
- [x] #34 Barrier thud (low thump + noise body scaled by pre-penalty impact speed; ≤2 concurrent in 150ms) — iOS
- [x] #35 Off-track rumble (lowpass noise loop while off-track, gain ∝ speed) — iOS
- [x] #36 Phase SFX themes (build-bay bed: low shop hum + distant clank every 10–25s; menu/garage keep the garage radio, which stops so the two never layer) — iOS
- [x] #38 Rain ambience (steady lowpassed-noise patter for the whole rainy race, fixed low gain) — iOS
- [x] #39 Garage ambience (wrench clink or compressor puff every 8–20s under the radio) — iOS
- [x] #40 Customer mumble-blips (pitched gibberish per speech bubble; skeptic low, rushed fast-high, bigspender jolly, regular neutral) — iOS
- [x] #51 Game Center leaderboards (GCManager: silent auth, per-track best-lap submit as centiseconds, results 🏆 dashboard) — iOS, behind `GAMECENTER_ENABLED` (off; needs paid account + 2 ASC leaderboards)
- [x] #52 iCloud save sync (NSUbiquitousKeyValueStore, last-write-wins by savedAtMs, "Synced from your other device" toast) — iOS, behind `ICLOUD_ENABLED` (off; needs iCloud capability)
- [x] #53 iPad layout pass (side-by-side garage/build panels, centered-form results sheet, race controls ≤96pt, topbar wrap fixes) — iOS, verified on iPad Air 13"
- [x] #54 Home-screen quick action ("Start a Race", flag.checkered → track picker; static Info.plist item + AppDelegate handler) — iOS
- [x] #55 Daily Lugnut widget (WidgetKit extension, small widget, App Group headline feed, midnight refresh) — iOS; device needs the App Groups capability
- [x] #56 Richer haptics (per-zone minigame ticks, steal click-click, rage triple thud, payout cascade) — iOS
- [x] #57 Live Activity race timer (lock screen + Dynamic Island, 1Hz, ends on finish/forfeit; fully local) — iOS
- [x] #58 App Intents ("Start a race" → track picker, "What's my best lap?" → spoken per-track bests) — iOS
- [x] #59 Per-phase orientation (Auto / Portrait / Landscape race via AppDelegate mask) — iOS
- [x] #60 Catalyst check (builds + runs on macOS; ActivityKit guarded, iOS-filtered widget embed) — iOS, destination kept enabled

## Earlier iOS batches (pre-backlog)

- Core port (garage loop, build bay, race, results, persistence)
- Pink-slip rival ladder, customer archetypes, owner on-scene
- Parts Catalog, Daily Lugnut, speech bubbles, crew hire, contracts board v1, the fence
- AudioEngine resilience (interruption/config-change recovery, fail-silent SFX)
- PBR materials + sky IBL, HDR bloom, particles/skids, body roll
- Battery governor (per-phase fps, thermal downshift), race pause overlay
- CoreHaptics (NOS rumble, barrier thuds, minigame ticks)
- VoiceOver audit, accessible minigame, Dynamic Type caps, Reduce Motion sweep

## Out of scope (web-only)

- #45 Keyboard minigame, #46 Gamepad race support (input devices)
- #48 Save export/import JSON *download/upload* (iOS uses share-sheet export; import not yet ported)
- #49 Three save slots (single save on iOS; backup via `sgs_save_prev` instead)
- #50 Cloud-save design doc
- #81/#82/#89/#91/#92/#98/#99/#100 (e2e harness, CI budgets, beta channel, analytics, OG tags, itch page, press kit, launch drafts)
