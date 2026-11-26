# Earshot: working on it

`Earshot/` is the addon. Copy it into `Interface\AddOns` to play with it.

## Tests

`tests/harness.lua` is a pretend WoW client: just enough of the game's API, checked
against the WoW Forever UI source (1.60.1), to run the addon's real code through 50
scenarios. It runs in Lua 5.1, the Lua that WoW uses:

```
pip install lupa
python tests/run.py
```

The scenarios cover walking away, turning around, the gap between lines, lines waiting in
Spoken's queue, logout, replays, dungeons, chatter (said, yelled and whispered), the
presets and the other sliders, the test sound, the minimap addon menu and the who's-talking
bubble, and giving back the nameplate options Earshot 0.3 changed for following (which
version 0.4 dropped; its last attempt is on the `following-experiment` branch).

The settings page is checked too: its sections, labels that fit, rows greying out while
Earshot is off (and being redrawn when the setting they depend on changes, as the game's
list does), and its Defaults button leaving the game's own options alone.

Spoken's queue is modelled through its public API (skip, stop, play now, remove, and
Spoken 3.12's Previous and Mute), so the five choices for walking out of earshot run
against it. The model also copies one quirk of the real Spoken: it tells addons a line has
started before it sets the line's timer. A line stopped during that call is later ended as
if it had played, and one skipped during it leaves the timer running, which can sound
Spoken's cue between lines at the wrong moment. Every scenario checks Earshot never does
either (it silences the line and skips or stops it a frame later).

The harness loads the files in `Earshot.toc`. It can't hear anything or see the real settings page or nameplates, so check
those in game with `/earshot test` and `/earshot status`.

GitHub runs the tests and builds the zip on every push (`.github/workflows/tests.yml`), and
attaches the zip to each release you publish (`.github/workflows/release.yml`).

## Building the zip

```
python tools/package.py
```

This runs the tests, then writes `dist/Earshot-<version>.zip` with the `Earshot` folder at
the top (what CurseForge and the game expect), plus `LICENSE` and `CHANGELOG.md`. The
version comes from `## Version` in `Earshot.toc`. `--no-tests` skips the tests.

## The test tune

`tools/make_tune.py` writes the music-box tune (an original melody) as a WAV file. Turn it
into the MP3 the addon plays with ffmpeg:

```
python tools/make_tune.py tune.wav
ffmpeg -i tune.wav -ac 1 -c:a libmp3lame -b:a 80k Earshot/Media/Test.mp3
```

If you change its length, change `LENGTH` in `Earshot/Test.lua` to match.

## The pictures

`tools/make_logo.py` draws the logo: `media/logo.svg` and `media/logo.png` (512×512, for
CurseForge and GitHub), `media/banner.png` (1280×640, for the README and GitHub's social
preview) and the icon in the game's addon list and minimap menu
(`Earshot/Media/Icon.tga`, 64×64). `tools/make_marker.py` draws the speech bubble that
marks who's talking. They need Pillow; the logo also needs `rsvg-convert` (librsvg) and the
Inter font for the banner:

```
pip install pillow
python tools/make_logo.py
python tools/make_marker.py Earshot/Media/Speaking.tga
```

## A new version

1. Bump `## Version` in `Earshot/Earshot.toc` and add a section to `CHANGELOG.md`.
2. `python tools/package.py`, and push.
3. Publish a GitHub release tagged `v<version>`. GitHub attaches the zip to it a minute or
   two later; the release workflow stops if the tag and the version don't match.
4. Upload the same zip to CurseForge.

Spoken changes often, so check Earshot against its newest release before each one.
