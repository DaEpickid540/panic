# Panic: Arena — Testing

## A. Test the game loop in the editor (no Firebase, no assets)

The project is built to run fully offline. With placeholder Firebase
credentials, `FirebaseManager.enabled` is `false` and all network calls no-op.

1. Open the project in Godot 4.6.3, press **F5** (main scene: `scenes/Main.tscn`).
2. In the **Lobby**: click **HOST GAME**, then **ADD TEST PLAYER** a few times
   (these are local stand-ins so role assignment has something to chew on).
3. Pick a **map** and drag the **round-length slider** (5–20 min).
4. Click **START GAME** → 5 s **Countdown** (pulsing red + beep) →
   **Hunting** spawns you on the map with the camera/speed for your role.
5. Move with **WASD** (+ mouse look if you rolled hunter). As hunter, click to
   **capture** a nearby test player → role flips to ghost, capture SFX fires,
   stats accrue.
6. Let the timer run out **or** capture all hunted → **End** screen with the
   survivor list + stats table. **BACK TO LOBBY** resets.

> Tip: to force a specific role while testing, call
> `GameManager.set_role(NetworkManager.local_peer_id, GameManager.Role.HUNTER)`
> from a breakpoint/console, or temporarily hard-code in `GameManager.assign_roles`.

## B. Full checklist (run against an exported build)

- [ ] Game loads in 3–5 s
- [ ] Lobby: player list updates, map selection works, timer slider works
- [ ] Countdown: 5 s countdown displays, beep plays
- [ ] Hunting: movement works (WASD + mouse / touch), positions sync (multi-tab)
- [ ] Capture: hunter raycast grabs hunted, role switches, capture SFX for all
- [ ] Ghost: ghost spawns, grabs hunted (≤3 m), screams, mutes hunted, 5 s escape
- [ ] End: ends on all-captured or timer; stats display
- [ ] Audio: hunted hears looping bed only; hunter hears 3D footsteps/screams;
      ghost hears nothing
- [ ] Mobile: UI scales, virtual joystick works, camera works
- [ ] PWA: installable, works offline (cached shell + assets)

## C. Multiplayer smoke test (requires Firebase)

1. Fill real credentials (see README "Wire up Firebase").
2. Deploy rules + functions.
3. Open the build in **two browser tabs**; HOST in one, JOIN the room code in
   the other. Confirm both see each other in the lobby and that positions sync
   during hunting (each avatar moves smoothly in the other tab).

## Known limitations (intentional placeholders)

- 3D models / textures are primitives until you drop Quaternius/Poly Haven
  assets in `assets/` (see ASSETS.md). Layout/collision are final.
- Audio is silent until you add CC0 `.ogg`/`.wav` files under
  `assets/audio/loops` and `assets/audio/sfx` (names listed in `AudioManager`).
- Fonts fall back to the engine default until Orbitron/Space Mono `.ttf`s are
  added and wired into `assets/panic_theme.tres`.
