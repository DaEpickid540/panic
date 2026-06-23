# Asset Source List — Panic: Arena

> **Status (installed):** Audio loops (8 `.mp3`), SFX (5), and 3D models
> (Kenney City Kit → Urban/Warehouse, Quaternius Nature → Forest) are in place
> and verified to import + build in Godot 4.6.3. See `CREDITS.md` for exact
> sources. **Still missing:** the two fonts below (`Orbitron`, `Space Mono`) —
> the UI falls back to the default font until the `.ttf` files are dropped in
> `assets/fonts/`. Mansion still uses procedural geometry (no model kit yet).

All sources below are free for commercial use. **Check each individual asset's
license at download time** — a site being "mostly CC0" does not guarantee every
file is. Record attributions in `CREDITS.md` as you add assets.

Drop files into:
- `assets/textures/`
- `assets/audio/`
- `assets/fonts/`

---

## Textures & Materials

| Source | License | Notes |
| --- | --- | --- |
| [Poly Haven](https://polyhaven.com/textures) | CC0 | PBR materials (concrete, metal, grime) — great for the arena. |
| [ambientCG](https://ambientcg.com/) | CC0 | Huge PBR texture library; download 1K/2K for web. |
| [Quaternius](https://quaternius.com/) | CC0 | Low-poly 3D model packs (characters, props) — ideal for HTML5 size budget. |
| [Kenney](https://kenney.nl/assets) | CC0 | UI icons, particle sprites, prototype textures. |

## Audio (horror SFX, ambience, music)

| Source | License | Notes |
| --- | --- | --- |
| [Freesound.org](https://freesound.org/) | Mixed (CC0 / CC-BY) | Filter by CC0; footsteps, heartbeats, whispers, screams. |
| [Zapsplat](https://www.zapsplat.com/) | Free w/ attribution (or paid no-attr) | Strong horror SFX catalog. |
| [YouTube Audio Library](https://www.youtube.com/audiolibrary) | Attribution-free | Dark ambient beds / drones for menus. |
| [Sonniss GDC Bundle](https://sonniss.com/gameaudiogdc) | Royalty-free | Annual free pro SFX packs. |

Target format for the web export: **`.ogg`** loops, **`.wav`** SFX. Keep the
whole audio set **< 50 MB** for fast HTML5 download. Drop files at these exact
paths (the engine loads them by name — missing files just stay silent):

```
assets/audio/loops/horror_01.ogg … horror_08.ogg   # 8 ambient loops (~2 min, seamless)
assets/audio/sfx/countdown_beep.wav
assets/audio/sfx/capture.wav
assets/audio/sfx/ghost_scream.wav
assets/audio/sfx/phase_change.wav
assets/audio/sfx/footstep.wav
```

3D models go in `assets/models/` (Quaternius `.glb`); swap them into
`MapBase._make_obstacle()` in place of the primitive boxes/cylinders.

## Fonts (dark / sci-fi)

| Font | License | Use |
| --- | --- | --- |
| [Orbitron](https://fonts.google.com/specimen/Orbitron) | SIL OFL 1.1 | Titles / display (the "PANIC: ARENA" logo). |
| [Space Mono](https://fonts.google.com/specimen/Space+Mono) | SIL OFL 1.1 | Body / HUD / monospace numerics. |

Download the `.ttf` files into `assets/fonts/`, then in Godot create a
`FontFile` and wire it into `assets/panic_theme.tres` (`default_font`).

---

## Quick attribution template (`CREDITS.md`)

```
- "<asset name>" by <author> — <source URL> — <license>
```
