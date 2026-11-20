# Solitaire for the Anbernic RG DS Plus (BananaOS)

Klondike Solitaire in LÖVE 11.5 (PortMaster). Gameplay and touch controls on the bottom screen; wallpaper and
stats on the top screen.

## Folder layout (matches the handheld's `/data/roms/ports/`)

```
Solitaire.sh                 launcher
SolitairProject/
  Solitaire.sh               (same launcher, kept beside the game)
  conf.lua  main.lua  src/  assets/
  assets/music/              your own songs (mp3, ogg, wav, flac)
  assets/backgrounds/        your own top-screen pictures (png, jpg)
```

On the handheld the game runs from `SolitairProject/Solitaire.love`, which is built from this folder.

## In-game updates (START > Check for updates)

The game looks at this repo's **latest release** for three files:

| file | what it is |
| --- | --- |
| `VERSION` | the version number, e.g. `0.3.0` |
| `SHA256` | the checksum of `Solitaire.love` |
| `Solitaire.love` | the game |

If `VERSION` is newer than the game's own version (`SolitairProject/src/version.lua`), the game offers to
install it. It downloads over HTTPS, checks the checksum, keeps the old game as `Solitaire.love.old`, swaps the
new one in, saves your game in progress, then tells you it will quit. Start it again to play the new version.
Your settings, stats, saved game, music and backgrounds are not touched. Needs wifi, and `curl` or `wget` on the device.

`Solitaire.sh` itself is **not** replaced by an update. If a release ever needs a new launcher, copy it over by hand.

## Publishing a new version

1. Make your changes. Raise the number in `SolitairProject/src/version.lua` (e.g. `0.2.0` -> `0.3.0`).
2. Run `python3 tools/make_release.py`. It writes `release/Solitaire.love`, `release/VERSION`, `release/SHA256`.
3. Commit and push the source (the `release/` folder is not committed).
4. On GitHub: **Releases > Draft a new release**, tag `v0.3.0`, attach those three files, **Publish**.
   Or with the GitHub CLI: `gh release create v0.3.0 release/Solitaire.love release/VERSION release/SHA256 --title "v0.3.0"`.
   Make it the **latest** release (not a pre-release or draft), because the game reads `releases/latest`.
