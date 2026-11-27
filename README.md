# Vox Pro

[![Tests](https://github.com/Obscuratea/vox-pro/actions/workflows/tests.yml/badge.svg)](https://github.com/Obscuratea/vox-pro/actions/workflows/tests.yml)

Audio mixer and router for Linux (PipeWire) with a plugin rack. Rust + Qt Quick. Not affiliated with
VB-Audio. The smaller version is [Vox](https://github.com/Obscuratea/vox-obscurus).

Made by [Obscuratea](https://github.com/Obscuratea), who designs Vox Pro, decides what it does and how it
looks, tests every release and publishes it. The code is written with Claude Code (an AI coding tool);
[TESTING.md](TESTING.md) says how it is tested.

![Vox Pro](docs/screenshots/main.png)

| Input inspector | Output inspector, recording |
| --- | --- |
| ![Inspector on the mic](docs/screenshots/inspector.png) | ![Inspector on a virtual mic](docs/screenshots/output.png) |

| Parametric EQ | Routing |
| --- | --- |
| ![Parametric EQ](docs/screenshots/eq.png) | ![Routing](docs/screenshots/routing.png) |

![Plugin rack](docs/screenshots/rack.png)

![Settings](docs/screenshots/settings.png)

## Features

Everything in Vox, plus:

- Up to 6 hardware inputs, 8 virtual inputs, 6 A outputs and 4 B virtual mics.
- Plugin rack: LV2, CLAP and VST3, up to six per channel, FX switch to bypass the chain.

Shared with Vox:

- Noise gate, bass, brightness, pitch and auto-duck on hardware inputs.
- Parametric EQ on every channel, compressor on every input, limiter on every output.
- Mono and Dim (−20 dB) on A outputs.
- Recording any output to FLAC, WAV or Opus.
- Routing page, solo, per-program mute, drag-to-route, scenes, custom channel names.
- Tray icon, global shortcuts (KDE Plasma), start with the computer, mute mics on screen lock.
- Sample rate and latency settings.
- Themes: Gold, Night, Glass, Light, or a picture background.
- Built-in updater (Settings → About).

## Plugins

Plugins are found in `/usr/lib/{lv2,clap,vst3}` and `~/.{lv2,clap,vst3}`. None are bundled. On Arch:
`lsp-plugins`, `calf`, `x42-plugins`, `dragonfly-reverb`.

- Add: install from your package manager and press **Rescan**, or drop a `.clap`, `.vst3` or `.lv2`
  onto the rack. Linux builds only.
- Controls are drawn by Vox; plugin windows are not shown.
- Instruments, MIDI plugins and plugins with more than two channels are not listed.
- If a plugin crashes Vox, the next start leaves it out.

## Requirements

A Linux system that uses **PipeWire** (0.3.77 or newer) with WirePlumber for its sound. Most current
distributions do: Fedora, Bazzite, SteamOS, Arch and CachyOS, Ubuntu 24.04 and newer, Linux Mint 22 and
newer, Debian 13. Systems that still use PulseAudio (for example Ubuntu 22.04 or Linux Mint 21) are not
supported. To check, run `pactl info | grep "Server Name"`: it should mention PipeWire.

Hardware:

- A 64-bit x86 PC (x86-64). ARM devices such as a Raspberry Pi or Snapdragon laptops are not supported yet.
- Graphics with OpenGL 2.1 or newer (integrated graphics are fine).
- About 300 MB of free memory.
- Room on screen for a 360 × 480 window.

Vox Pro works on sound in real time. On a current desktop CPU it uses about 1–2 %; slower CPUs, more
channels and effects, or a lower latency setting use more. Plugins add their own CPU and memory use.

## Install

Downloads are on the [Releases page](https://github.com/Obscuratea/vox-pro/releases).

**Any distribution: the AppImage.** One file that runs on its own, nothing to install. Download
`vox-pro-*-x86_64.AppImage`, make it runnable and start it:

    chmod +x vox-pro-*-x86_64.AppImage
    ./vox-pro-*-x86_64.AppImage

(Or right-click it, Properties, allow it to run as a program, then double-click it.) Keep it somewhere
permanent, such as `~/Applications`: "Check for updates" in Settings replaces this file with the new version.
To add it to your app menu, use [Gear Lever](https://flathub.org/apps/it.mijorus.gearlever) or your
desktop's own AppImage support. The AppImage has no blur behind the Glass themes on KDE Plasma (they are
still see-through); the Arch package has it.

**Arch, CachyOS, EndeavourOS, Manjaro: the package.** Download `vox-pro-*-x86_64.pkg.tar.zst`, then:

    sudo pacman -U vox-pro-*-x86_64.pkg.tar.zst

Tested AppImage systems are listed in [TESTING.md](TESTING.md#the-appimage-on-other-distributions).

## Build

Needs Rust, clang, cmake, Qt 6 (base, declarative, widgets), KWindowSystem, PipeWire, SoundTouch and lilv.

    cargo run --release

Settings: `~/.config/vox-pro/settings.json` (plus a `.bak`). Run Vox Pro or Vox, not both.

## Support

- Ko-fi: https://ko-fi.com/obscuratea
- Patreon: https://patreon.com/Obscuratea
- Discord: https://discord.gg/uqV26sCQFq

Bugs and ideas go on the Issues page. Code contributions are not accepted.

## Licence

Free to use, including commercially. Not open source: no modifying, redistributing, forks or resale.
See [LICENSE](LICENSE). Third-party licences: [THIRD_PARTY.txt](THIRD_PARTY.txt).
