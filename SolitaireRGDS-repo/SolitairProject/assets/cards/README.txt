=== CARD ASSET IMPORT GUIDE ===

Place your PNG card files here in this folder (`assets/cards/`).

SUPPORTED FILE NAMING FORMATS:
The game engine automatically recognizes any of the following standard naming formats:

Format 1 (Recommended):
- {rank}_{suit}.png
  Examples:
  1_hearts.png, 2_hearts.png, ..., 13_hearts.png
  1_diamonds.png, ..., 13_diamonds.png
  1_clubs.png, ..., 13_clubs.png
  1_spades.png, ..., 13_spades.png

Format 2 (Short Suit):
- {rank}_{suit_initial}.png  or  {rank}{suit_initial}.png
  Examples:
  1_H.png, 10_S.png, 13_C.png, 1_D.png
  AH.png, 10S.png, KC.png, QD.png

Format 3 (Suit First):
- {suit}_{rank}.png
  Examples:
  hearts_1.png, spades_13.png, etc.

CARD BACK:
- Name your card back image: `card_back.png` (or `back.png`).

NOTE ON RESOLUTION & TRANSPARENCY:
- Recommended card resolution: 116 x 164 pixels (or larger with transparent background; LÖVE will scale smoothly).
- If any card PNG is missing, the game automatically uses its built-in procedural high-res card renderer as a fallback, so the game will never crash!

