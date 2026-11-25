#!/usr/bin/env python3
"""Generate a Roblox .rbxlx place file containing the full Beastbound tree."""
import xml.sax.saxutils as sax
import xml.etree.ElementTree as ET
import pathlib

SRC = pathlib.Path("/workspace/beastbound/src")
OUT = pathlib.Path("/workspace/beastbound/build/Beastbound_TheGreatMigration.rbxlx")

class Item:
    def __init__(self, cls, name):
        self.cls = cls
        self.name = name
        self.props = []  # list of (kind, key, value) — Name handled separately
        self.children = []
    def prop(self, kind, key, value):
        self.props.append((kind, key, value))
        return self
    def add(self, child):
        self.children.append(child)
        return self

def emitter(item: Item, out: list):
    emitter.n += 1
    out.append(f'<Item class="{item.cls}" referent="RBX{emitter.n}">')
    out.append("<Properties>")
    out.append(f'<string name="Name">{sax.escape(item.name)}</string>')
    for kind, key, value in item.props:
        out.append(f'<{kind} name="{key}">{sax.escape(value)}</{kind}>')
    out.append("</Properties>")
    for child in item.children:
        emitter(child, out)
    out.append("</Item>")
emitter.n = 0

def named_script(path: pathlib.Path, name: str):
    cls = "ModuleScript"
    if path.name.endswith(".client.lua"):
        cls = "LocalScript"
    return Item(cls, name).prop("ProtectedString", "Source", path.read_text())

def add_scripts(folder: pathlib.Path, parent: Item):
    for p in sorted(folder.glob("*.lua")):
        name = p.name.removesuffix(".client.lua").removesuffix(".server.lua").removesuffix(".lua")
        parent.add(named_script(p, name))

rs = Item("ReplicatedStorage", "ReplicatedStorage")
shared = Item("Folder", "BeastboundShared")
add_scripts(SRC / "shared", shared)
rs.add(shared)

sss = Item("ServerScriptService", "ServerScriptService")
bootstrap = SRC / "server/BeastboundModules/BeastboundBootstrap.server.lua"
sss.add(Item("Script", "BeastboundBootstrap").prop("ProtectedString", "Source", bootstrap.read_text()))
mods = Item("Folder", "BeastboundModules")
for p in sorted((SRC / "server/BeastboundModules").glob("*.lua")):
    if p.name == "BeastboundBootstrap.server.lua":
        continue
    mods.add(named_script(p, p.stem))
sss.add(mods)

sp = Item("StarterPlayer", "StarterPlayer")
sps = Item("StarterPlayerScripts", "StarterPlayerScripts")
add_scripts(SRC / "client", sps)
sp.add(sps)

ws = Item("Workspace", "Workspace")
lighting = Item("Lighting", "Lighting")

out = ['<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">']
for svc in (ws, lighting, rs, sss, sp):
    emitter(svc, out)
out.append("</roblox>")
xml_text = "\n".join(out) + "\n"

ET.fromstring(xml_text)

def index(root):
    idx = {}
    for it in root.iter("Item"):
        name = it.find("Properties/string[@name='Name']").text
        src = it.find("Properties/ProtectedString[@name='Source']")
        idx[name] = src.text if src is not None else None
    return idx

embedded = index(ET.fromstring(xml_text))
count = 0
for p in list((SRC / "shared").glob("*.lua")) + list((SRC / "server/BeastboundModules").glob("*.lua")) + list((SRC / "client").glob("*.lua")):
    name = p.name.removesuffix(".client.lua").removesuffix(".server.lua").removesuffix(".lua")
    if embedded.get(name) != p.read_text():
        raise SystemExit(f"roundtrip mismatch: {p.name}")
    count += 1

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(xml_text)
print(f"OK {OUT} bytes={OUT.stat().st_size} scripts={count} xml=valid roundtrip=exact")
