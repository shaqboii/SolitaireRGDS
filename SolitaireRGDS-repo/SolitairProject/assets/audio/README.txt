=== AUDIO ASSET IMPORT GUIDE ===

Place your sound effects here in `assets/audio/` when you are ready to import sound.
Supported audio formats: `.wav`, `.ogg`, or `.mp3`.

Supported sound filenames:
- `flip.wav`    / `flip.ogg`    -> Played when selecting / turning a card
- `place.wav`   / `place.ogg`   -> Played when placing or auto-placing a card
- `draw.wav`    / `draw.ogg`    -> Played when drawing from stock (Y button or tap)
- `shuffle.wav` / `shuffle.ogg` -> Played when starting a new deal
- `undo.wav`    / `undo.ogg`    -> Played on Undo action
- `error.wav`   / `error.ogg`   / `error.mp3` -> Played when a card is placed somewhere it can't go (the cards also shake)
- `win.wav`     / `win.ogg`     -> Played on victory

- `win_song.mp3` / `.ogg` / `.wav` -> A song that starts after win.mp3 has finished. Loops until you start a new game
- `lose.mp3` / `.ogg` / `.wav`   -> Played when the game detects the deal can no longer be won
                                       (if missing, error.mp3 is played instead)

NOTE:
If audio files are not present, audio calls are safely skipped without any errors.

