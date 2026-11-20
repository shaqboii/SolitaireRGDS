# Klondike Solitaire for Anbernic RG DS Plus (BananaOS)

A native, high-resolution **Klondike Solitaire** game built with **LÖVE (Love2D)** specifically tailored for the **Anbernic RG DS Plus** running **BananaOS**.

---

## 🎮 Hardware & Dual-Screen Layout

* **Target Device:** Anbernic RG DS Plus
* **OS:** BananaOS (BananaLinux)
* **Screens:** Dual 4:3 displays at **1024 × 768** resolution each ($1024 \times 1536$ stacked canvas)
* **Top Screen ($1024 \times 768$):**
  * Displays a customizable still wallpaper or an animated texture/GIF loop (Wallpaper Engine style).
  * Ambient floating card particles with subtle glow (default procedural fallback).
  * Real-time stats panel: **Score**, **Time Elapsed**, **Move Count**, and **Foundations Progress**.
  * On-screen controller button reference pill.
  * Victory celebration fanfare when you win.
* **Bottom Screen ($1024 \times 768$):**
  * Interactive green felt solitaire table.
  * Full capacitive **touchscreen support** (tap, drag-and-drop, and double-tap).
  * Physical **D-Pad cursor navigation** and gamepad controls.

---

## 🕹️ Controls Guide

| Input | Action |
| :--- | :--- |
| **D-Pad (Up / Down / Left / Right)** | Navigate cursor across Stock, Waste, Foundations, and Tableau cards |
| **A Button** | **Toggle Selection** (pick up card / place selected card on target) |
| **Hold L or R Trigger + A** | **Auto-Place**: Instantly sends the focused/selected card to Foundation or best Tableau spot |
| **Y Button** | **Draw 1** card from the Stock pile to Waste |
| **B Button** | Deselect / Cancel current selection |
| **Select / Back Button** | **Undo** (unlimited undos with score rollback) |
| **Start Button** | Deal a **New Game** |
| **Touch: Tap Card** | Select card or move selected card to tapped pile |
| **Touch: Tap Stock** | Draw 1 card |
| **Touch: Drag & Drop** | Drag single card or card stacks across tableau columns and foundations |
| **Touch: Double-Tap** | Auto-place card directly to Foundation |
| **Touch: On-screen Buttons** | Dedicated **UNDO** and **DEAL** buttons on the top row |

---

## 📁 Importing Your Custom Assets

The game includes a **built-in procedural card and background generator**—so it runs immediately out of the box with crisp vector cards even before you import any files. When you're ready to import:

### 1. Card Sprites (`assets/cards/`)
Drop your PNG card files into `assets/cards/`. Any of these standard naming conventions work automatically:

* **Format 1 (Recommended):** `{rank}_{suit}.png`
  * Examples: `1_hearts.png`, `10_spades.png`, `13_clubs.png`
  * Ranks: `1` (Ace) through `13` (King). Suits: `hearts`, `diamonds`, `clubs`, `spades`.
* **Format 2 (Short Suit):** `{rank}_{suit_initial}.png` or `{rank}{suit_initial}.png`
  * Examples: `1_H.png`, `10S.png`, `KC.png`, `AD.png`
* **Format 3 (Suit First):** `{suit}_{rank}.png`
  * Examples: `hearts_1.png`, `spades_13.png`
* **Card Back:** Name your card back `card_back.png` (or `back.png`).

### 2. Top Screen Background / Animations (`assets/backgrounds/`)
* **Still Image:** Drop a $1024 \times 768$ image named `top_bg.png` or `top_bg.jpg`.
* **Animated Texture / GIF Frames:** Create a subfolder `assets/backgrounds/animated/` and drop numbered PNG frames (`frame_001.png`, `frame_002.png`, etc.). The game cycles through them in a smooth loop.

### 3. Sound Effects (`assets/audio/`)
Supported formats: `.wav`, `.ogg`, or `.mp3`.
* `flip.wav` – Card selection
* `place.wav` – Card placement / auto-place
* `draw.wav` – Stock draw
* `shuffle.wav` – New game deal
* `undo.wav` – Undo move
* `win.wav` – Victory fanfare

---

## 🚀 How to Run on BananaOS (Anbernic RG DS Plus)

1. Connect your MicroSD card or access your device over SFTP/Wi-Fi.
2. Copy the `SolitairProject` folder to `/roms/ports/` on your SD card.
3. Make sure `Solitaire.sh` has executable permissions:
   ```bash
   chmod +x /roms/ports/SolitairProject/Solitaire.sh
   ```
4. On your RG DS Plus, navigate to the **Ports** menu and select **Solitaire**!

---

## 💻 Testing on PC (Windows / Linux / macOS)

To test or iterate on your computer:
1. Ensure [LÖVE (Love2D)](https://love2d.org/) is installed.
2. In PowerShell or Command Prompt, run from this folder:
   ```powershell
   love .
   ```
3. Use the arrow keys (D-pad), `Space`/`Enter` (A button), `Y` (Draw 1), `Shift` or `L`/`R` (Triggers), `Esc` (B button), and `U`/`Z` (Undo), or simply use your mouse / touchscreen.

