# NepoCleanse

A debuff-removal helper for World of Warcraft 1.12, built from the ideas and data of
[Rinse](https://github.com/Shaykh/Rinse), redesigned to stay out of the way.

## What it does

- Lists debuffs your class can remove, on the people you choose, and removes one when you click its row
  (or press the key binding, or run `/nc go` from a macro).
- Runs only inside dungeons, raids and battlegrounds (each can be switched off). Everywhere else it is
  fully off: no events, no timers, nothing on screen.
- Watches only the people on your list, in the order you set:
  - **My list** – starts with your friends list; add, remove and reorder names (Top / Up / Down).
  - **Raid list** – filled with **Import raid**: main tanks first (from pfUI tank marks or CT_RaidAssist),
    then paladins, priests and shamans, then everyone else. Kept until you import again.
  - The selected tab is the list in use.
- Reads a person again only when their auras change, instead of checking everyone on a timer.

## Settings

`/nepocleanse` or `/nc` opens the settings window:

- **People** – the two lists, with search.
- **Debuffs** – hide debuffs or show them first; search; see what has turned up this session.
- **Title bar** – show or hide the bar and its parts, name, colour, height, text size, background.
- **General** – where it runs, watch yourself too, skip Abolish, sound, lock, rows, size.

Other commands: `/nc on` (run everywhere), `/nc auto` (instances only), `/nc go` (remove the first debuff in range).

On the list: click a row to remove the debuff, Shift + right-click to stop showing that debuff,
drag the title bar to move it, right-click the title bar for settings.

## Install

Put the files in `Interface/AddOns/NepoCleanse/`. Turn off Rinse if you use it.
Works best with SuperWoW (casts without changing your target) and UnitXP (range and line of sight).
