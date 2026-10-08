#!/usr/bin/env python3
"""Apply Hamster's original static Lua registration to the pinned sources."""
from pathlib import Path
import shutil
import sys

source, lua = (Path(value) for value in sys.argv[1:])
target = source / "plugins/lua"
if target.exists():
    shutil.rmtree(target)
shutil.copytree(lua, target, ignore=shutil.ignore_patterns(".git"))
# Enable Lua's own iOS compatibility path for APIs such as system().
lua_cmake = target / "CMakeLists.txt"
lua_cmake.write_text(lua_cmake.read_text() + "\ntarget_compile_definitions(rime-lua-objs PRIVATE LUA_USE_IOS)\n")
api = source / "src/rime_api.cc"
text = api.read_text()
if "extern void rime_require_module_lua();" not in text:
    text = text.replace("extern void rime_require_module_levers();", "extern void rime_require_module_levers();\nextern void rime_require_module_lua();", 1)
    text = text.replace("  rime_require_module_levers();", "  rime_require_module_levers();\n  rime_require_module_lua();", 1)
    api.write_text(text)
assert "  rime_require_module_lua();" in api.read_text()
cmake = source / "CMakeLists.txt"
cmake.write_text(cmake.read_text().replace("add_subdirectory(tools)", "# Only the iOS static library is built."))
