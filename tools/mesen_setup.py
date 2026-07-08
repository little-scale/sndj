#!/usr/bin/env python3
"""mesen_setup.py — ensure Mesen 2's saved settings suit headless checks.

The testrunner uses the same settings.json as the GUI; on a fresh install
port 1 has no controller attached, which silently breaks emu.setInput in
check scripts. Run automatically by `make check`.
"""
import json
import os
import sys

PATH = os.path.expanduser("~/Library/Application Support/Mesen2/settings.json")


def main():
    if not os.path.exists(PATH):
        print("mesen_setup: no settings.json yet (first run will create it)")
        return
    d = json.load(open(PATH, encoding="utf-8-sig"))
    changed = []
    port1 = d.setdefault("Snes", {}).setdefault("Port1", {})
    if port1.get("Type") != "SnesController":
        port1["Type"] = "SnesController"
        changed.append("controller on port 1")
    sw = d.setdefault("Debug", {}).setdefault("ScriptWindow", {})
    if not sw.get("AllowIoOsAccess"):
        sw["AllowIoOsAccess"] = True  # shot.lua writes PNGs from Lua
        changed.append("script io/os access")
    if changed:
        json.dump(d, open(PATH, "w"), indent=1)
        print("mesen_setup: " + ", ".join(changed))
    else:
        print("mesen_setup: ok")


if __name__ == "__main__":
    sys.exit(main())
