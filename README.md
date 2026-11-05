# KJV_Bible

A small, movable panel that shows verses from the King James Bible.
Includes the complete KJV text (66 books, 31,102 verses).

## Install
1. Copy the `KJV_Bible` folder into your game's `Interface\AddOns\` folder.
2. In game, check the Interface number with:
   `/run print(select(4, GetBuildInfo()))`
   and put that number on the `## Interface:` line of `KJV_Bible.toc`.
   (Or tick "Load out of date AddOns" on the character-select AddOns screen.)

## Use
- Left-drag to move, right-click for a random verse, mouse wheel to read
  backward and forward through the text.
- `/kjv John 3:16`, `/kjv 1 cor 13:4-7`, `/kjv psalm 23` - look up any passage
  (ranges show up to 8 verses).
- `/kjv next` / `prev`, `random`, `daily`, `find <words>`.
- `/kjv source favorites|all` - daily/random verses come from the favorites
  list (default) or the whole Bible.
- `/kjv mode daily|random`, `interval <min>`, `lock`/`unlock`, `scale`,
  `width`, `reset`. `/kjv help` lists everything.

## Files
- `Bible\*.lua` - full text, one file per book (generated; don't hand-edit).
- `Verses.lua` - favorite references; add your own, e.g. `"Psalm 23:1-3",`.
- `Core.lua` - panel and commands.

## Text source
King James Version (public domain), from the scrollmapper/bible_databases
project. Dashes and apostrophes were converted to plain ASCII, and the Hebrew
letters in the Psalm 119 headings were removed (the game fonts can't show them).
This edition prints "Lord" where printed KJVs use small-caps "LORD".
