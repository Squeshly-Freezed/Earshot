"""Runs Earshot's scenario tests in Lua 5.1 (the Lua WoW uses)."""
import sys
from pathlib import Path

from lupa import lua51

ROOT = Path(__file__).resolve().parent.parent
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.globals().ADDON_DIR = str(ROOT / "Earshot")
report, failed = lua.execute((ROOT / "tests" / "harness.lua").read_text())
print(report)
sys.exit(1 if failed else 0)
