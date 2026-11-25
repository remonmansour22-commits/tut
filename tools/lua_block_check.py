#!/usr/bin/env python3
"""Luau block-balance checker: verify every file's block keywords balance."""
import re, sys, pathlib

ROOT = pathlib.Path("/workspace/beastbound")

def strip_literals(src: str) -> str:
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("--[[", i) or src.startswith("--[=[", i):
            eq = src[i+2:i+3] if src.startswith("--[=[", i) else ''
            close = "]" + eq + "]"
            j = src.find(close, i)
            i = n if j == -1 else j + len(close)
        elif src.startswith("--", i):
            j = src.find("\n", i)
            i = n if j == -1 else j
        elif c in "\"'":
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == c or src[j] == "\n":
                    break
                j += 1
            i = j + 1
        elif src.startswith("[[", i) or src.startswith("[=[", i):
            eq = src[i+1:i+2] if src.startswith("[=[", i) else ''
            close = "]" + eq + "]"
            j = src.find(close, i)
            i = n if j == -1 else j + len(close)
            out.append(" ")
        else:
            out.append(c)
            i += 1
    return "".join(out)

TOKEN = re.compile(r"\b(function|if|for|while|do|repeat|until|then|else|elseif|end)\b")

def check(path: pathlib.Path) -> list:
    src = strip_literals(path.read_text())
    lines = src.splitlines()

    def line_of(pos: int) -> int:
        return src.count("\n", 0, pos) + 1

    stack = []
    pending_loop = False
    for m in TOKEN.finditer(src):
        t = m.group(1)
        if t == "function" or t == "if" or t == "repeat":
            stack.append((t, line_of(m.start())))
        elif t == "for" or t == "while":
            stack.append((t, line_of(m.start())))
            pending_loop = True
        elif t == "do":
            if pending_loop:
                pending_loop = False
            else:
                stack.append((t, line_of(m.start())))
        elif t == "until":
            if stack and stack[-1][0] == "repeat":
                stack.pop()
            else:
                return [f"line {line_of(m.start())}: 'until' with no matching repeat"]
        elif t == "end":
            if stack:
                stack.pop()
            else:
                return [f"line {line_of(m.start())}: extra 'end'"]
        elif t == "then" or t == "else" or t == "elseif" or t == "for":
            pass
    if stack:
        return [f"unclosed '{k}' opened at line {ln}" for k, ln in stack]
    return []

fail = 0
for p in sorted(ROOT.rglob("*.lua")):
    rel = p.relative_to(ROOT)
    errs = check(p)
    if errs:
        fail += 1
        for e in errs:
            print(f"FAIL {rel}: {e}")
    else:
        print(f"ok   {rel}")
sys.exit(1 if fail else 0)
