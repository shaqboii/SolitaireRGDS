=== AUDIO ASSET IMPORT GUIDE ===

Place your sound effects here in `assets/audio/` when you are ready to import sound.
Supported audio formats: `.wav`, `.ogg`, or `.mp3`.

Supported sound filenames:
- `flip.wav`    / `flip.ogg`    -> Played when selecting / turning a card
- `place.wav`   / `place.ogg`   -> Played when placing or auto-placing a card
- `draw.wav`    / `draw.ogg`    -> Played when drawing from stock (Y button or tap)
- `shuffle.wav` / `shuffle.ogg` -> Played when starting a new deal
- `undo.wav`    / `undo.ogg`    -> Played on Undo action
- `error.wav`   / `error.ogg`   / `error.mp3` -> Played when a card is placed somewhere it can't go
- `win.wav`     / `win.ogg`     -> Played on victory

NOTE:
If audio files are not present, audio calls are safely skipped without any errors.

