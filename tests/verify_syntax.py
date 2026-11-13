import os
import glob
import re

base_dir = r"c:\Users\Frank Targa\Desktop\roblox\src"
lua_files = glob.glob(os.path.join(base_dir, "**", "*.lua"), recursive=True)

all_clean = True
for f in lua_files:
    rel = os.path.relpath(f, base_dir)
    with open(f, "r", encoding="utf-8") as fp:
        code = fp.read()
    
    # Strip block comments --[[ ... ]]
    code = re.sub(r"--\[\[.*?\]\]", "", code, flags=re.DOTALL)
    # Strip line comments
    code = re.sub(r"--.*", "", code)
    # Strip double-quoted strings
    code = re.sub(r'"([^"\\]|\\.)*"', '""', code)
    # Strip single-quoted strings
    code = re.sub(r"'([^'\\]|\\.)*'", "''", code)
    
    p = code.count("(") - code.count(")")
    b = code.count("{") - code.count("}")
    k = code.count("[") - code.count("]")
    
    if p != 0 or b != 0 or k != 0:
        print(f"MISMATCH in {rel}: parens={p}, braces={b}, brackets={k}")
        all_clean = False
    else:
        print(f"CLEAN: {rel}")

if all_clean:
    print(f"\nAll {len(lua_files)} Luau files have balanced syntax!")
else:
    exit(1)
