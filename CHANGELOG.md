# Changelog

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
