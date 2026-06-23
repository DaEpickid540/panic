# Panic: Arena — Upgrade Pass (autonomous session)

A set of self-contained, low-risk upgrades that build on existing systems.
All GDScript only, mobile-compatible, no new external assets required.

## 1. Sprint + Stamina (Survivors)
The `sprint` input action already existed but was unused. Survivors can now
**hold Shift (or the mobile SPRINT button) to run faster**, draining a green
stamina bar. Stamina regenerates when you're not sprinting.

- Base survivor speed 6.0 → sprint 8.1 m/s (still slower than a hunter's dash
  burst, so the hunter can still catch up — but survivors get a real escape tool).
- Stamina lasts ~2.5s of sprinting, refills in ~4.5s.
- New green **STAMINA** bar on the HUD (survivors only).

## 2. Map Pickups
Floating, spinning collectibles scattered around every map. They respawn ~20s
after being grabbed, and each one only helps the role that needs it:

- **Battery** (yellow) — instantly refills the **hunter's** flashlight.
- **Adrenaline** (green) — refills a **survivor's** stamina and gives a short
  speed boost.

Built entirely in code (`Pickup.gd` + `PickupManager.gd`), spawned by
GameController when the hunt begins and cleaned up on teardown.

## 3. Settings (persisted)
A new settings block in the lobby:

- **Master volume** slider.
- **Look sensitivity** slider (affects mouse + touch look).

Saved to `user://settings.cfg` and reloaded on launch.

## 4. Persistent Stats / Progression
Your results are saved to `user://stats.cfg`:

- Best survival time, total captures, games played.
- Shown on the lobby ("BEST: mm:ss") and the end screen.

## 5. Capture Kill-Feed
A small toast appears on the HUD whenever someone is caught
("NAME WAS CAUGHT"), fading out after a couple of seconds. Pure feel/feedback.

---
Each feature is isolated so one breaking doesn't affect the others. See the
matching comments in each script for how it works.

# Pass 2 — Horror & Maps

## 6. Manual role choice
Lobby profile now has an **AUTO / HUNTER / RUNNER** toggle
(`GameManager.role_preference`). `assign_roles()` honors it — picking HUNTER
makes you the hunter every round, RUNNER hands the hunter role to a bot so you
always run. (Works perfectly vs bots; in full lobbies it's a best-effort.)

## 7. Fully-indoor Mansion + thick walls
Mansion is rebuilt as an **enclosed building** (Murder-Mystery-2 style): a sealed
exterior (4 m thick walls + ceiling) with interior partition walls forming rooms
and doorway-connected corridors. No outside plot to wander to.

- Exterior walls thickened on **every** map (was 1 m → 2 m open / 4 m indoor) so
  dashing/fast players can't tunnel through.
- `MapBase._build_indoor_layout()` drives the room generator; `_make_partition()`
  builds walls with doorway gaps.

## 8. Clipping fixes
- **Bots** now raycast their *actual* step each frame and refuse to move when a
  wall is in the way (they used to slide into walls on deflection).
- **Thrown weapons** already raycast prev→new position vs world geometry; the
  thicker walls make this airtight.

## 9. Dynamic flickering lights
`FlickerLight.gd` — accent + ceiling lights flicker like failing wiring, and get
more agitated (faster, more blackouts) once the hunt begins.

## 10. Heartbeat camera shake
Survivors' camera thumps with a heartbeat that beats faster and harder the closer
the hunter gets (`PlayerController._update_heartbeat_shake`, driven by `fear`).

## 11. Fear-linked stamina
The `fear` value (how close the hunter is) now **burns sprint stamina faster and
slows its recovery** — panic literally tires you out.

---
## Still queued (bigger content systems, not yet built)
- Environmental storytelling: blood trails, notes, broken objects.
- Glitch FX: screen tearing, corrupted textures, UI distortion.
- Shadow entities that move only when you're not looking.
- Fake-hunter mirages.
- Hiding spots (lockers) with a 30 s auto-kick.
- Breathing system (needs a breath SFX file).
- Lights that react to the monster's *position* (currently react to hunt phase).
