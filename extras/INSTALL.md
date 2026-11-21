# ZenOS Custom UI, Highlight Suite & Games Bundle

Fork: `https://github.com/tylermiranda/zen-os` (`zen-custom` branch, based on `v4.3.2`)

## What's Included
1. **Pastel 5-Color Highlight Suite** (`zenos.koplugin`):
   - **Instant Save**: Selecting text saves the highlight immediately in your last-used color and shows a compact swatch circle + icon bar (`Note`, `Dictionary`, `Translate`, `AI Assistant`, `Search`, `Pin`, `Delete`).
   - **5 Named Categories**:
     - Yellow (`#F6DF96`) — **Quotes**: Great writing, memorable lines, or favourite passages.
     - Blue (`#B8D8F8`) — **Core Ideas**: Key story turning points in fiction, or main arguments in non-fiction.
     - Green (`#BCE5C8`) — **Context**: Lore, character backgrounds, historical dates, or definitions.
     - Red (`#DFC5F2`) — **Reactions**: Scenes that surprised you, made you laugh, or hit hard emotionally.
     - Orange (`#FAD0B4`) — **Action**: Questions to research, unfamiliar words, or practical advice to apply.
   - **Grayscale + Color E-Ink Support**: Swatches render pastel RGB fills on color screens and distinct stepped shades + letter monograms (`Q`, `I`, `C`, `R`, `A`) on grayscale Carta screens.
   - **1-Row-Per-Category Color Picker** with descriptions (`ReaderHighlight:showHighlightColorDialog`).
   - **Kobo Nickel Importer** (`common/kobo_import.lua`): Settings → Reader → Annotation viewer → *Import Kobo highlights & notes* reads `/mnt/onboard/.kobo/KoboReader.sqlite`.
2. **Reader Polish**:
   - Bigger green folded-corner bookmark (`green_folded_bookmark = true`).
   - Single full-waveform e-ink flash on menu open (`menu_open_flash = true`).
   - Cleaned-up top menu tabs (`clean_reader_top_menu = true`).
3. **Launcher, Navigation & Bluetooth Exit**:
   - Wide `Library` card tile (`span = 2`) and `Games` tile (`span = 2` folder) in ZenOS App Launcher.
   - Looping menu/library pages (`loop_pages = true`) + full refresh on page turn (`full_refresh_on_page_turn = true`).
   - Bluetooth-aware Exit prompt (`common/shutdown.lua`): asks to reboot instead of exiting to Nickel if Bluetooth was enabled during the session.
4. **Games Plugins** (`games/`):
   - `sudoku.koplugin`
   - `boardgames.koplugin` (Minesweeper with colored numbers, `⚑` flag icons, and upright `16×30` Expert board)
   - `murdoku.koplugin` (distinct room tints and offline-first launch with no Wi-Fi prompt)

## Manual USB Install
Copy into `/Volumes/KOBOeReader/.adds/koreader/plugins/`:
- `zenos.koplugin/`
- `games/sudoku.koplugin/`
- `games/boardgames.koplugin/`
- `games/murdoku.koplugin/`

## Backup Location on Tower
`/data/OpenBot/Shared/kobo-zen-ui/backups/2026-11-21/`
