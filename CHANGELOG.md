# Changelog

## 0.4.1

- Mark who's talking says what's missing when its bubble can't show. The bubble sits on
  nameplates, and friendly NPCs only have them with the game's Friendly NPC nameplates on
  (and, for NPCs other than your target, Always Show Nameplates). Since 0.4 Earshot doesn't
  switch those on, so the first time a voice plays without them it says how to see the
  bubble, once. Ticking Mark who's talking without them, and `/earshot status`, say so too.
- The guide says which nameplate options the bubble needs.

## 0.4.0

- Follow speakers by nameplate is gone, with Hide friendly NPC nameplates and Show NPC
  titles. The game won't tell addons where an NPC stands, so following had to guess from
  rough distance checks and where the nameplate sat on screen, and it guessed wrong too
  often: walking away from a quest giver, the voice could stay at one volume. Voices are
  placed as before: where the NPC stood when you talked to it, and chatter where you were
  when the NPC spoke.
- If you had following on, the nameplate options it turned on (Friendly NPC nameplates and
  Always Show Nameplates) go back to how you had them, the first time 0.4 loads on each
  character. One you've changed yourself since stays as you have it.
- The speech bubble over whoever's talking shows when you have friendly NPC nameplates on in
  the game's options.
- Earshot no longer includes LibStub or LibRangeCheck-3.0.
- The author is listed as SqueshlyFreezed, the name used on CurseForge and Buy Me a Coffee.
- The guide says where to report bugs.

## 0.3.3

First public release.

- Spoken's NPC voices fade as you walk away from whoever is talking, and go softer when the
  speaker is behind you. Quest and gossip lines come from where the NPC stood when you
  talked to it, and world chatter from where you were when the NPC spoke. Yells carry
  further, and whispers play as normal.
- Presets (Subtle, Natural, Dramatic), plus sliders for how close a voice stays at full
  volume, where it fades out, how loud a speaker behind you is, how quiet a voice may get,
  and how far chatter and yells carry.
- When you walk out of earshot: keep playing quietly, skip the line, skip that NPC's lines,
  skip every NPC out of earshot, or wait until you come back.
- Follow speakers by nameplate (off by default) keeps track of the talking NPC while it
  speaks. Friendly NPC nameplates are cut down to their names (with titles such as
  `<Stable Master>` underneath) and can't be clicked. Your own nameplate options come back in
  combat and when you switch it off.
- A speech bubble over the NPC who's talking, also for NPC lines that only show in chat.
- Works with Spoken 3.12: a line you go back to with Previous plays as normal from a
  distance, and while Spoken is muted Earshot leaves your volume alone.
- A settings page (Esc > Options > AddOns > Earshot, the minimap addon menu, or `/earshot`)
  that greys out while Earshot is off, and whose Defaults button leaves the game's own sound
  options alone. `/earshot test`, `/earshot status`, a status line in the minimap addon
  menu's tooltip, and `Earshot:Place` / `Earshot:Done` for other voice addons.
- Your volume always comes back: after each line, when you switch Earshot off, at logout and
  on `/reload`.

Versions 0.1 to 0.3.2 were private test builds.
