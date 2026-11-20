#!/usr/bin/env python3
"""Builds the three files the game's "Check for updates" looks for, into ./release/:

    Solitaire.love   the game (zip of conf.lua, main.lua, src/, assets/)
    VERSION          the number from SolitairProject/src/version.lua
    SHA256           the checksum of Solitaire.love

Run from anywhere:  python3 tools/make_release.py
Then attach those three files to a new GitHub release (see README.md).
"""
import hashlib
import os
import re
import sys
import zipfile

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
proj = os.path.join(root, "SolitairProject")
out = os.path.join(root, "release")

m = re.search(r'number\s*=\s*"(\d+\.\d+\.\d+)"', open(os.path.join(proj, "src", "version.lua")).read())
if not m:
    sys.exit("Could not read the version from SolitairProject/src/version.lua")
version = m.group(1)

os.makedirs(out, exist_ok=True)
love = os.path.join(out, "Solitaire.love")
with zipfile.ZipFile(love, "w", zipfile.ZIP_DEFLATED) as z:
    for top in ("conf.lua", "main.lua", "src", "assets"):
        path = os.path.join(proj, top)
        if os.path.isfile(path):
            z.write(path, top)
        else:
            for dirpath, _, files in os.walk(path):
                for name in sorted(files):
                    full = os.path.join(dirpath, name)
                    z.write(full, os.path.relpath(full, proj).replace(os.sep, "/"))

digest = hashlib.sha256(open(love, "rb").read()).hexdigest()
open(os.path.join(out, "VERSION"), "w").write(version + "\n")
open(os.path.join(out, "SHA256"), "w").write(digest + "  Solitaire.love\n")
print("Built release", version)
print("  ", love, os.path.getsize(love), "bytes")
print("   sha256", digest)
