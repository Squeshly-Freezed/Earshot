# Earshot

NPC voices fade as you walk away from whoever is talking, and go softer when the
speaker is behind you. Made for [Spoken](https://www.curseforge.com/wow/addons/spoken)
on WoW Forever.

## Setup

1. Put the `Earshot` folder in the same `Interface\AddOns` folder as Spoken, then type
   `/reload` in game.
2. In Spoken's settings, set **Volume Follows** to **Ambience Volume**. Type
   `/earshot spoken` to open them. Spoken starts on Master Volume, and Earshot won't
   fade that, because Master carries every sound in the game.
3. Type `/earshot test` outdoors. A tune plays a few steps in front of you. Walk away and
   turn around: it fades, and goes softer behind you.

Leave Spoken's **Stop When Window Closes** (on its Quests page) off, as it is to begin
with. With it on, Spoken stops a quest line as soon as you walk off and the window closes,
so there's nothing left to fade.

## Settings

Three ways in: Esc > Options > AddOns > Earshot, the addon menu on the minimap (the button
that lists your addons), or type `/earshot`.

| Setting | Default | What it does |
|---|---|---|
| Fade voices with distance | on | Switches Earshot on and off. |
| Preset | Natural | Sets the distance sliders and the chatter range together: Subtle, Natural or Dramatic. Shows Custom once you move one. |
| Full volume within | 10 yd | How close to the speaker a voice stays at full volume. |
| Silent beyond | 45 yd | Where a voice has faded out completely. |
| Volume behind you | 65% | How loud a speaker directly behind you sounds. 100% switches this off. |
| Never quieter than | 0% | The quietest a placed voice gets, however far you walk. |
| When you walk out of earshot | Keep playing quietly | Or skip the line, skip everything that NPC has to say, skip every NPC you're out of earshot of, or wait until you come back. See below. |
| Quest and gossip voices | on | Lines read from an NPC's window. |
| World chatter | on | NPCs talking around you. |
| Chatter heard up to | 45 yd | How far from where an NPC spoke its chatter fades out. Full volume within about half of that. |
| Yells heard up to | 120 yd | The same for yells. At the top of the slider, Anywhere, yells aren't faded. |
| Follow speakers by nameplate | off | Keeps track of the talking NPC while it speaks. See below. |
| Hide friendly NPC nameplates | on | While following, friendly NPC nameplates show only their names, and can't be clicked. |
| Show NPC titles | on | Titles such as <Stable Master> under those names. |
| Mark who's talking | on | A speech bubble over the NPC who's talking. See below. |
| Also NPCs talking without a voice | on | The bubble for lines that only show in chat too. |

While Earshot is switched off, its other settings are greyed out. Two of the game's own
sound options sit there too, because they shape how its world sounds carry: **Distance
filtering** (muffles far-away sounds) and **Reverb**. The page's Defaults button resets
Earshot's settings and leaves those two alone. At the bottom: a test sound, a check of your
setup, and a shortcut to Spoken's settings.

Commands: `/earshot test`, `/earshot status`, `/earshot spoken`, `/earshot on`, `/earshot off`,
`/earshot help`. Hover over Earshot in the minimap addon menu to see whether it's on.

## Good to know

- **It moves a slider.** WoW gives addons no way to place a sound in the world or set the
  volume of one sound. Earshot moves the volume slider Spoken plays on while a line
  plays, then puts it back. On Ambience Volume, birdsong and wind fade along with the
  voice during a line. You'll also see that slider move in Options > Audio. If you drag
  it yourself mid-line, Earshot lets go and keeps your new level.
- **Distance and facing, not left and right.** An addon can't pan a sound to one ear, so
  "behind you" is a softer voice, not a voice that comes from behind.
- **Where the NPC is, roughly.** The game doesn't tell addons where an NPC stands. When
  its window opens you're next to it and facing it, so Earshot notes that spot, a couple
  of yards ahead of you.
- **World chatter is a guess.** The game doesn't say which way a talking NPC is, so the
  voice stays at full volume until you're about 20 yards from where you were when the NPC
  spoke (with Chatter heard up to at 45). Yells carry further. Whispers are said to you,
  so they play as normal.
- **Spoken's voices, not the game's.** Earshot fades what Spoken voices: quest and gossip
  lines, and NPC talk and yells. The game plays its own voiced lines itself, and Earshot
  can't change the volume of one sound, so it leaves them alone (the bubble still marks
  who's talking). Players' chat, yells included, has no voice, so there's nothing to fade.
- **Replays play as normal.** A line you replay, start from a distance, or go back to with
  Spoken's **Previous** button isn't faded. Earshot fades a voice you walk away from; it
  doesn't start one silent.
- **Spoken muted?** Then lines are words only, and Earshot leaves the slider alone.
- **Lines waiting in Spoken's queue stay faded.** Talk to a few NPCs in a row and Spoken
  plays their lines one after another. If you walk off before a line's turn comes, it
  starts faded (or silent), because you were in earshot when the NPC said it.
- **Out of earshot.** A moment after you're past a voice's fade-out distance, **When you
  walk out of earshot** decides what happens:
  - **Keep playing quietly:** the line carries on, faded out.
  - **Skip the line:** Spoken moves on to its next line.
  - **Skip that NPC's lines:** the line and everything else that NPC has waiting. Lines
    it says while you're still away are skipped too.
  - **Skip every NPC out of earshot:** the line, and every line waiting from any NPC
    you're out of earshot of. A line that starts while you're out of earshot of it is
    skipped at once, before you hear it. Whispers, and lines you play yourself from a
    distance (from the quest log, say), still play.
  - **Wait until you come back:** Spoken stops a quest or gossip line, and plays it again
    from the start when you walk back (Spoken can't carry on mid-line). Other lines still
    play meanwhile. Chatter you walk away from is skipped: it was a passing remark.

  Skipped a line you wanted after all? Spoken's **Previous** button brings it back.
- **Outdoors only.** In dungeons, raids, battlegrounds and arenas the game hides positions
  from addons, so voices play as normal. Walk into one mid-line and that line fades out.
- **Your level always comes back.** At the end of each line, when you switch Earshot off,
  at logout and on `/reload`.
- Zone stories, books and dungeon voices play as normal: they come from no one standing
  anywhere.

## Following the speaker

Without it, Earshot places a voice once: where the NPC stood when you talked to it, or for
world chatter, where you were when the NPC spoke. With **Follow speakers by nameplate**
on, it keeps checking the talking NPC's nameplate while the line plays:

- **How far away it is.** The game won't give addons an NPC's position, but it will
  answer "is it within X yards?" for a few distances. Earshot asks through
  [LibRangeCheck-3.0](https://www.curseforge.com/wow/addons/librangecheck-3-0): 8 and 28
  yards, 5 for NPCs that can be healed or buffed, and, if your class has healing or buff
  spells, as far as those reach (often 30 and 40). Between those steps Earshot keeps its
  own estimate, so it knows roughly where the NPC is, not exactly.
- **Which way.** Where the nameplate sits on screen, and whether the game says the NPC is
  behind the camera. This is used while you're moving or holding the right mouse button,
  when the camera faces where your character does.

So chatter is no longer stuck where you heard it, and an NPC who walks with you (an
escort) stays in earshot.

To have nameplates to read, following turns on two of the game's options while you're out
of combat: **Friendly NPC nameplates**, and **Always Show Nameplates** (with it off, out of
combat only your target has a nameplate). With **Hide friendly NPC nameplates** on,
Earshot then hides everything on friendly NPC nameplates except their names, and makes
them unclickable. Once an NPC has a nameplate, the game shows its name there instead of
above its head, so that's where NPC names come from now. They still follow your NPC name
settings. Nameplates don't show titles such as <Stable Master>, so **Show NPC titles**
adds them underneath, read from the NPC's tooltip.

Enemy and player nameplates aren't touched, but Always Show does mean enemy nameplates
also show outside combat, unless something switches them off then: Leatrix Plus's
**Combat plates** does, and works as before alongside Earshot.

Following pauses in combat, because the game blocks the distance checks on friendly NPCs
then. Spoken keeps talking: a voice Earshot was following stays at the volume it had when
the fight started (the NPC may be an escort fighting beside you), and following picks up
again when the fight ends. A quest giver Earshot wasn't following stays where you talked
to it, so its voice still fades as you move. As a fight starts, your own nameplate
settings also come back until it ends. Switch following off and they come back for good.
The game saves nameplate options per character, so Earshot remembers yours per character
too.

Following only works outdoors. If a nameplate addon such as Plater draws your
nameplates, hide friendly NPCs in its settings instead. Following still works.

## Who's talking

With **Mark who's talking** on, a small speech bubble sits over the NPC whose voice is
playing. It goes on the NPC's nameplate, so it needs one: with Follow speakers by
nameplate on, or with friendly NPC nameplates switched on yourself.

**Also NPCs talking without a voice** puts the bubble over NPCs whose words only show in
chat too, including the game's own lines that Spoken has no voice for. The game doesn't
say when its own voice clips end, so that bubble stays for about as long as the line
takes to say. Whispers aren't marked, and neither are the short greetings NPCs make when
you click on them: the game doesn't tell addons about those.

## For other voice addons

Any addon playing its voice on the Ambience, Music or Dialog slider can use Earshot:

```lua
-- When your line starts:
local token = Earshot and Earshot:Place({ channel = "Ambience", guid = UnitGUID("npc") })
-- or, for a speaker you can't identify, pinned where the player stands:
-- Earshot:Place({ channel = "Ambience", here = true })

-- When it ends:
if token then Earshot:Done(token) end
```

`Place` returns nil when Earshot can't place the sound (switched off, indoors, an NPC it
hasn't seen). Optional fields `full` and `silent` (yards) override the player's settings.

## Files

| File | What it does |
|---|---|
| `Core.lua` | Settings defaults, position and facing helpers, start-up and logout. |
| `Math.lua` | Distance, direction and the loudness curves. No game calls, so it's easy to test. |
| `Volume.lua` | Borrows one volume slider and always gives it back. |
| `Anchors.lua` | Notes where each NPC stood when you talked to it. |
| `Spatial.lua` | Follows you while a voice plays and sets the slider 20 times a second. |
| `Plates.lua` | Follows the speaker by its nameplate, hides friendly NPC nameplates and adds their titles. |
| `Markers.lua` | The speech bubble over the NPC who's talking. |
| `SpokenLink.lua` | Listens to Spoken's lines and chat, and handles walking out of earshot. |
| `API.lua` | The `Earshot:Place` / `Earshot:Done` functions for other addons. |
| `Test.lua` | `/earshot test`. |
| `Options.lua` | The settings page, the minimap addon menu entry and `/earshot`. |
| `Media/` | The test tune, the minimap icon and the speech bubble. |
| `Libs/` | LibStub (public domain) and LibRangeCheck-3.0 (MIT, licence included). |
