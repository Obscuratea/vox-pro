#!/usr/bin/env python3
"""Write THIRD_PARTY.txt for a Vox project: the About screen shows it (embedded by src/bridge.rs).
Usage: gen_third_party.py PROJECT_DIR APP_NAME [--pro]"""
import subprocess, sys, re, collections, os

proj, app = sys.argv[1], sys.argv[2]
pro = "--pro" in sys.argv

out = subprocess.run(["cargo", "tree", "-e", "normal", "--prefix", "none", "--format", "{p}|{l}"],
                     cwd=proj, capture_output=True, text=True, check=True).stdout
crates = {}
for line in out.splitlines():
    name, _, lic = line.partition("|")
    name = re.sub(r" \((/|\*|proc-macro).*?\)", "", name).replace(" (*)", "").strip()
    lic = lic.replace(" (*)", "").strip() or "unspecified"
    if name.startswith(app.lower().replace(" ", "-") + " "):
        continue
    crates[name] = lic
groups = collections.defaultdict(list)
for name, lic in sorted(crates.items()):
    groups[lic].append(name)

t = []
t.append(f"{app} uses the free software below. Thank you to everyone who makes it.\n")
t.append("LGPL LIBRARIES (shared libraries on your system)\n")
t.append("""Qt 6 - GNU LGPL version 3 - https://www.qt.io
  The interface is built with Qt. Qt is not part of the {app} program: it is the copy installed on your
  system (the qt6-base and qt6-declarative packages), used as a shared library. You may replace it with your own
  build of Qt. The licence text is at /usr/share/licenses/qt6-base/LGPL-3.0-only.txt and at
  https://www.gnu.org/licenses/lgpl-3.0.html. Qt's source is at https://download.qt.io/official_releases/qt/.

SoundTouch - GNU LGPL version 2.1 - https://www.surina.net/soundtouch
  The pitch shifter. Also used as a shared library from your system (the soundtouch package); you may replace it
  with your own build. The licence text is at /usr/share/licenses/spdx/LGPL-2.1-only.txt and at
  https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html. Source: https://codeberg.org/soundtouch/soundtouch.
""".replace("{app}", app))
t.append("OTHER LIBRARIES\n")
t.append("PipeWire - MIT - https://pipewire.org  (talks to your sound system)\n")
if pro:
    t.append("""Opus codec (libopus) - BSD 3-clause - https://opus-codec.org
  Copyright (c) 2001-2023 Xiph.Org, Skype Limited, Octasic, Jean-Marc Valin, Timothy B. Terriberry,
  CSIRO, Gregory Maxwell, Mark Borgerding, Erik de Castro Lopo, Mozilla, Amazon. Built into {app} for Opus
  recordings. Redistribution and use in source and binary forms, with or without modification, are permitted
  provided that the copyright notice, this list of conditions and the disclaimer in the full licence
  (https://opus-codec.org/license/) are kept.

flacenc - Apache 2.0 - https://github.com/yotarok/flacenc-rs  (FLAC recordings)
""".replace("{app}", app))
t.append("""
RUST LIBRARIES
The program is written in Rust with the crates below, each under the licence shown (all permissive: you may
read their full texts on https://crates.io/crates/NAME).
""")
for lic, names in sorted(groups.items(), key=lambda kv: -len(kv[1])):
    t.append(f"\n{lic}\n  " + ", ".join(names) + "\n")
open(os.path.join(proj, "THIRD_PARTY.txt"), "w").write("\n".join(t))
print(f"{len(crates)} crates, {len(groups)} licence groups")
