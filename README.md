# Panic: Arena

A multiplayer horror hide-and-seek game built in **Godot 4.6.3**, exported to **HTML5 / PWA** with **Firebase** multiplayer.

Each round drops players into a dark, procedurally-generated arena. One (or more) players are the **Hunter**. Everyone else **runs**.

---

## Roles

| Role | View | Speed | Goal |
|------|------|-------|------|
| **Hunter** | First-person, flashlight | 5 m/s + dash | Stab and throw weapons at runners. Must use BOTH melee and throws to down someone. |
| **Hunted** | First-person, garbage flashlight | 6 m/s + sprint | Power generators to escape. 5 HP with progressive injuries. |
| **Ghost** | First-person, noclip flight | 2 m/s | Grief the living with lightning strikes, fake killers, and grabs. |

## Controls

| Action | Desktop | Mobile |
|--------|---------|--------|
| Move | `WASD` | Virtual joystick |
| Look | Mouse | Touch drag |
| Jump | `Space` | Jump button |
| Sprint (runner) | `Shift` | Sprint button |
| Dash (hunter) | `Shift` | Dash button |
| Melee (hunter) | `LMB` | Tap |
| Throw weapon (hunter) | `RMB` | Throw button |
| Flashlight | `F` | Light button |
| Hide in locker | `E` | — |
| Pause / Menu | `Esc` | — |

## Game Flow

```
LOBBY  -->  COUNTDOWN (5s)  -->  HUNTING (3-20 min)  -->  END
```

- **Lobby:** Host picks map, weapon, round time, killer count. Joiners see mirrored settings.
- **Hunting:** Runners power generators (6 spawned, 5 needed to escape). Hunter tracks them down.
- **End:** Runners escape if generators are powered. Hunter wins if all runners are caught.

## Features

- **11 maps** — Urban, Forest, Warehouse, Mansion, Neon, Graveyard, Maze, Dungeon, School, Cave, Lab
- **8 weapons** — Knife, Cleaver, Axe, Katana, Sword, Hammer, Pickaxe, Baseball Bat
- **Anti-camp system** — Killers loitering near generators with no runners nearby get teleported away
- **Progressive injury** — Runners slow down, lose stamina, and repair generators slower as they take damage
- **Horror systems** — Jumpscares, vignette blindness, heartbeat audio, glitch overlays, shadow entities, mirages
- **Bot opponents** — Add bots for solo testing or to fill lobbies
- **PWA support** — Install on mobile home screen for fullscreen play
- **Settings** — Volume, look sensitivity, fog strength, killer count, debug overlay

## Getting Started

### Requirements
- **Godot 4.6.3** (standard GDScript build)
- **Firebase** project with Realtime Database + Anonymous Auth enabled

### Setup
1. Clone the repo and open `project.godot` in Godot
2. Copy `firebase_config.example.json` to `firebase_config.json` and fill in your Firebase credentials
3. Deploy database rules: `firebase deploy --only database`
4. Press **F5** to run — the game works offline with bots, no Firebase needed for testing

### Build for Web
```powershell
.\build.ps1          # release build
.\build.ps1 debug    # debug build
```

**Always use the build script**, not the Godot editor export dialog. The editor re-enables PWA headers that break Firebase.

### Deploy
```bash
firebase deploy --only hosting
```

## Project Structure

```
panic/
  project.godot          # autoloads, input map, export config
  scripts/               # all game logic (GDScript)
    GameManager.gd       # phases, roles, settings, timer         (autoload)
    FirebaseManager.gd   # REST client for Firebase RTDB          (autoload)
    NetworkManager.gd    # peers, rooms, bots                     (autoload)
    GameStateSync.gd     # match state sync over Firebase         (autoload)
    AudioManager.gd      # 8 ambient loops + SFX                  (autoload)
    PlayerController.gd  # first-person movement, combat, flashlight
    RemotePlayer.gd      # remote player avatars + bot AI
    MapBase.gd           # procedural arena generator (10 styles)
    GameController.gd    # match orchestration
    Generator.gd         # runner objectives
    HuntingUI.gd         # in-game HUD
    LobbyUI.gd           # lobby interface
  scenes/                # Godot scene files
    maps/                # 10 map scenes (reference MapBase.gd)
  assets/                # models, textures, audio, fonts
  pwa/                   # manifest.json, service worker, icons
  firebase/              # database rules, hosting config
  build.ps1              # web export script (Windows)
```

## Credits

See [CREDITS.md](CREDITS.md) for full asset attribution.

**Developer:** Sarvin (@DaEpickid540)  
**Engine:** [Godot 4.6.3](https://godotengine.org) (MIT)  
**Multiplayer:** [Firebase](https://firebase.google.com) Realtime Database
