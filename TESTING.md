# How Vox Pro is tested

Vox Pro is made by Obscuratea, who designs it, decides what it does and how it looks, tests every release
on a real desktop and publishes it. The code is written with Claude Code (an AI coding tool). This page
says what is checked before a release, what is checked by hand, and what is not tested yet.

## Automatic tests

`Scripts/test.sh` runs all of them. GitHub runs the same script on a fresh Arch Linux machine on every
push; each run and its full log are public on the
[Actions page](https://github.com/Obscuratea/vox-pro/actions/workflows/tests.yml).
`Scripts/release.sh` will not build a release unless every test passes.

**1. Unit tests** (`cargo test`), in the source files next to the code they check:

| Area | What is checked |
| --- | --- |
| Engine | The PipeWire version check (old Debian and Ubuntu versions are refused), Mono and Dim, solo, push to talk, auto-duck and its recovery, the limiter ceiling, removing a channel while others keep playing, telling devices apart from Vox's own streams |
| Effects | Compressor ratio, pitch shift (octaves, no dropouts at other buffer sizes), the strip EQ |
| Parametric EQ | Bells, shelves, pass filters and notch, cells that are off, output gain, old saves brought into range |
| Plugins | A missing plugin leaves a silent slot and the sound untouched, dropped plugins are checked before they are copied, external plugins are told apart from LV2 ones, saved slots are cleaned up |
| Settings | Older settings files (including 0.2) still load with their values and layout, the old three-band EQ becomes EQ cells, limits on channel counts, unique labels and names |
| Recording | WAV length, FLAC checked by the reference `flac` decoder, Opus checked with `ffmpeg` |
| Updater | Version comparison, a release needs both its package and its checksum; the AppImage updates from the release's AppImage, and only a real AppImage replaces it (a web page or broken download leaves the old file untouched) |
| Start with the computer | The autostart entry runs this program |

**2. Interface tests** (`tests/qml`, run without a screen): the program lists. Badges on sound card outputs,
the send-back button, dragging a program out of a list, dragging it onto a strip, a short drag that should
do nothing.

**3. Any x86-64 CPU:** the release build is checked for AVX-512 instructions, which crash older CPUs.

## Checked by hand

Five tests need a running desktop or installed plugins, so the automatic runs skip them. Run them with
`cargo test --release -- --ignored`:

- devices follow the settings live (needs PipeWire)
- global shortcuts bind and key presses arrive (needs KDE Plasma)
- the update path up to the password prompt
- a real LV2 plugin loads, runs and obeys its controls (needs the plugin installed)
- every installed external plugin loads and runs

Each release is installed and used on a real desktop before it is published. Some changes go out
first as test builds (GitHub pre-releases) to testers. Release notes list the systems a release was
tested on (OS and desktop).

## The AppImage on other distributions

`Scripts/test_appimage.sh` starts the AppImage in a fresh container of each distribution below, with that
distribution's own PipeWire and WirePlumber, and checks that all of Vox's devices appear in PipeWire.
It runs without a screen, so it checks that the program starts and works with that PipeWire, not how it
looks or sounds there.

| Distribution | glibc | PipeWire | Result |
| --- | --- | --- | --- |
| Ubuntu 24.04 LTS (also Linux Mint 22, Pop!_OS 24.04) | 2.39 | 1.0.5 | works |
| Ubuntu 25.10 | 2.42 | 1.4.7 | works |
| Debian 13 | 2.41 | 1.4.2 | works |
| Fedora 42 | 2.41 | 1.4.11 | works |
| Fedora 43 (also Bazzite) | 2.42 | 1.4.11 | works |
| Arch Linux | 2.44 | 1.6.12 | works |
| openSUSE Tumbleweed | 2.44 | 1.6.11 | works |
| Debian 12 | 2.36 | 0.3.65 | does not start: too old for both |

Last run 2026-11-27. The first run found two libraries that Debian 13 and Fedora 42 don't always have;
the AppImage now carries them.

## Not tested yet

- Desktops other than KDE Plasma and niri. Other distributions are tested in containers (below), not yet on
  their real desktops.
- Audio actually flowing through PipeWire in the automatic tests (planned: a headless PipeWire with test
  devices on GitHub's machines).
- Most of the interface: the mixer strips, EQ dragging, Settings and the tray have no interface tests yet.

## Bug fixes get tests

A fixed bug gets a test where possible, so it stays fixed. Release notes say when a fix is covered by one.

- 0.3.1, dragged program pills got stuck or clipped: `tests/qml/tst_streamlist.qml`
- 0.3.1, crash on CPUs without AVX-512: step 3 of `Scripts/test.sh`
- 0.3.2, sending a program back: `tests/qml/tst_streamlist.qml`

## Reporting a bug

Open an issue with your distribution, your desktop (KDE, GNOME, niri…), the Vox version and what
happened.
