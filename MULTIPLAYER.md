# Panic: Arena — Multiplayer setup & deploy

Multiplayer uses **Firebase Realtime Database** as the transport (anonymous auth +
REST, polled for live updates). It works the same on desktop and the HTML5 build.
Until you add real Firebase credentials the game runs **offline** (solo + bots),
which is the default.

> These steps need your own Firebase account and the `firebase` CLI. They are
> documented here but must be run by **you** — I can't log into your account or
> deploy on your behalf.

## 1. Create the Firebase project (one time)

1. <https://console.firebase.google.com> → **Add project**.
2. **Build → Authentication → Sign-in method → Anonymous → Enable.**
   (The client signs in anonymously; the DB rules require `auth != null`.)
3. **Build → Realtime Database → Create database** (start in *locked* mode —
   we ship rules below).
4. **Project settings → General → Your apps → Web app (`</>`)** → register an
   app and copy the `firebaseConfig` values.

## 2. Add your credentials to the build

```bash
cp firebase_config.example.json firebase_config.json
# edit firebase_config.json with your apiKey / databaseURL / etc.
```

`firebase_config.json` lives at the project root, is **gitignored**, and is baked
into the export (read by `FirebaseManager`). With valid values the game prints
`Online — anonymous auth OK` at startup instead of the OFFLINE message.

## 3. Install the CLI & log in (one time)

```bash
npm install -g firebase-tools
firebase login
firebase use --add        # pick the project you created
```

## 4. Deploy the database rules

```bash
cd firebase
firebase deploy --only database        # pushes database.rules.json
cd -
```

## 5. Build the web client & deploy hosting

```bash
./build.ps1            # or ./build.sh  → outputs build/html5/
cd firebase
firebase deploy --only hosting         # serves ../build/html5
cd -
```

Your game is now live at `https://<project>.web.app`.

## 6. Play together

- Player A opens the site → **HOST GAME** → a 6-letter **ROOM CODE** appears.
- Player B opens the site → types that code in **JOIN** → **JOIN**.
- B shows up in A's lobby roster. **A presses START** (only the host can start;
  joiners follow automatically).

## How it works / limits

- **Transport:** `FirebaseManager.db_listen()` polls each watched path (~0.2 s for
  positions, ~0.5–1 s for state/roster) and re-emits it, so there's no SSE/JS
  bridge to break. Expect ~quarter-second latency, which is fine for hide-and-seek.
- **Presence:** each client heartbeats `games/<room>/players/<id>` every 3 s;
  peers missing for 9 s are dropped (covers crashes/closed tabs).
- **Authority:** the host owns phase/roles/captures; everyone owns their own
  position. Grief (lightning / fake-killer / melee) is routed so it lands on the
  victim's own client.
- **Not yet networked:** remote ghosts' *visuals* (the bolt, the decoy body) are
  still spawned only on the caster's screen — the victim feels the effect but
  doesn't see the source. Full entity replication would be the next step.
- Threads are **disabled** in the web export, so `firebase.json` intentionally
  omits the COOP/COEP headers (they would block the cross-origin Firebase calls).
