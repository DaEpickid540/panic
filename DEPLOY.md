# Panic: Arena — Deployment

> These steps require your own accounts (itch.io / GitHub / Firebase). They are
> documented here and scripted where possible, but must be run by you — they are
> not performed automatically by this repo.

## 0. Build first

```bash
./build.sh           # or  .\build.ps1   on Windows
# output: build/html5/  (index.html, *.wasm, *.pck, *.js, manifest, SW)
```

Keep the total under **50 MB** (use low-poly assets + `.ogg` audio; the export
preset enables VRAM texture compression for mobile).

## 1. itch.io (HTML5 game)

1. Zip the **contents** of `build/html5/` (not the folder itself):
   ```bash
   cd build/html5 && zip -r ../panic-arena-web.zip . && cd -
   ```
2. On itch.io → **Create / Edit project**:
   - **Kind of project:** HTML
   - Upload `panic-arena-web.zip`, tick **"This file will be played in the browser"**.
   - **Embed options:** set viewport to e.g. 1280×720, tick **Fullscreen button**
     and **Mobile friendly**.
   - If you enabled engine threads, also tick **"SharedArrayBuffer support"**.
     (This preset ships with threads **disabled**, so you usually don't need it.)
3. Add screenshots + description, save, and view.

## 2. GitHub Pages

```bash
# one-time: create an orphan gh-pages branch
git checkout --orphan gh-pages && git rm -rf . || true
cp -r build/html5/* .
echo "" > .nojekyll          # don't let Jekyll eat _-prefixed files
git add . && git commit -m "Deploy web build"
git push origin gh-pages
git checkout -
```

Enable **Settings → Pages → Branch: gh-pages /(root)**. Note: GitHub Pages does
**not** send COOP/COEP headers, so engine threads must stay disabled (they are).

## 3. Firebase Hosting (optional, gives you headers + same origin as the DB)

`firebase/firebase.json` already sets the WASM mime type and COOP/COEP headers.
Point `hosting.public` at the build and deploy:

```bash
cp -r build/html5/* firebase/public/        # or set "public": "../build/html5"
cd firebase
firebase deploy --only hosting,database,functions
```

## After deploying

- Put the **itch.io** and **GitHub Pages** URLs in `README.md` (placeholders
  are marked `<!-- LINK -->`).
- Re-run the [TESTING.md](TESTING.md) checklist against the live URL on desktop
  Chrome/Firefox/Safari and at least one phone.
