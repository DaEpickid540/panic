# Panic: Arena — Web build helper (Windows / PowerShell).
#
# IMPORTANT: export from the COMMAND LINE (this script), NOT the Godot editor's
# Export dialog. The GUI dialog rewrites export_presets.cfg and re-enables the
# PWA service worker + cross-origin-isolation headers, which BLOCK Firebase
# (auth + multiplayer) in the browser. This script honours the cfg as-is
# (PWA disabled in Godot) and deploys our OWN manifest + service worker that
# does NOT add COEP headers.
#
# Prereqs: Godot 4.6.3 + web export templates installed. Set $env:GODOT or it
# falls back to the known path under Downloads.
#
# Usage:  .\build.ps1            (release)
#         .\build.ps1 debug

param([string]$Mode = "release")
$ErrorActionPreference = "Stop"

$Godot = if ($env:GODOT) { $env:GODOT } else { "C:\Users\daepi\Downloads\_godot463\Godot_v4.6.3-stable_win64_console.exe" }
$Out = "public"

New-Item -ItemType Directory -Force -Path $Out | Out-Null

Write-Host "==> Exporting Web ($Mode) to $Out/ with $Godot"
if ($Mode -eq "debug") {
  & $Godot --headless --export-debug "Web" "$Out/index.html"
} else {
  & $Godot --headless --export-release "Web" "$Out/index.html"
}

# Strip Godot's PWA leftovers (they inject COEP headers that block Firebase).
Write-Host "==> Removing Godot PWA leftovers"
Remove-Item "$Out/index.manifest.json","$Out/index.offline.html" -ErrorAction SilentlyContinue

# Deploy our custom manifest + service worker (no COEP, Firebase-safe).
Write-Host "==> Deploying custom PWA manifest + service worker"
Copy-Item "pwa/manifest.json" "$Out/manifest.json" -Force
New-Item -ItemType Directory -Force -Path "$Out/icons" | Out-Null
if (Test-Path "pwa/icons") {
  Copy-Item "pwa/icons/*" "$Out/icons/" -Force
}
Copy-Item "pwa/service-worker.js" "$Out/sw.js" -Force

# Inject manifest link + SW registration into index.html if not already present.
$html = Get-Content "$Out/index.html" -Raw -Encoding utf8
if ($html -notmatch 'manifest\.json') {
  $html = $html -replace '</head>', @'
<link rel="manifest" href="manifest.json">
<meta name="theme-color" content="#CC0000">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="mobile-web-app-capable" content="yes">
<script>if('serviceWorker' in navigator){navigator.serviceWorker.register('sw.js');}</script>
</head>
'@
  [System.IO.File]::WriteAllText("$Out/index.html", $html, [System.Text.UTF8Encoding]::new($false))
  Write-Host "==> Injected PWA tags into index.html"
}

Write-Host "==> Done. Now deploy:  firebase deploy --only hosting"
