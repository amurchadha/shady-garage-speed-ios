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
- #33–#36, #38–#40 (extra audio beds: skid, off-track rumble, build-bay hum, rain/garage ambience, mumble blips) — candidates for a later audio pass
- #21–#30 batch-5 juice (cam yaw lag, speed lines, impact shake, slow-mo finish, photo mode, confetti, countdown pan, entrance variety, owner flinch, minimap pulse)
