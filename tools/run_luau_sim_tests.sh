#!/usr/bin/env bash
# Executes the UNIT CLASH Roblox simulation in the real Luau VM.
# Copies the actual sources into a scratch dir with a tiny Roblox shim in
# front of each module, then runs tools/luau_sim_tests.lua. The repo sources
# themselves are never modified.
#
# Usage: tools/run_luau_sim_tests.sh [path-to-luau]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LUAU="${1:-luau}"
WORK="$(mktemp -d /tmp/uc_luau_XXXXXX)"
S="$ROOT/unit-clash-roblox/src"

if ! command -v "$LUAU" >/dev/null 2>&1; then
  echo "error: luau interpreter not found at '$LUAU'" >&2
  echo "get it from https://github.com/luau-lang/luau/releases (luau-ubuntu.zip)" >&2
  exit 2
fi

cat > "$WORK/uc_shim.lua" <<'EOF'
-- Test shim: fake Roblox services/globals so the real sim modules load unmodified.
local registry = {}
local function inst(name) return { Name = name } end
local mods = {}
for _, n in ipairs({ "UCConfig", "UCRng", "UCSimCore", "UCModes", "UCLab" }) do mods[n] = inst(n) end
local shared = { WaitForChild = function(_, n) if n == "UCConfig" then return mods.UCConfig end end }
local RS = { WaitForChild = function(_, n) if n == "UCShared" then return shared end end }
local modulesDir = { WaitForChild = function(_, n) return mods[n] end }
local M = {}
M.game = {
  GetService = function(_, n)
    if n == "ReplicatedStorage" then return RS end
    error("GetService not shimmed in headless tests: " .. tostring(n))
  end,
}
M.scriptFor = function(name) return { Parent = modulesDir, Name = name } end
M.Color3 = { fromRGB = function(r, g, b) return { r = r, g = g, b = b } end }
M.Enum = { Material = setmetatable({}, { __index = function(_, k) return { name = k } end }) }
M.task = { wait = function() end }
M.require = function(target)
  local file = ({
    UCRng = "uc_rng_copy",
    UCConfig = "uc_config_copy",
    UCSimCore = "uc_simcore_copy",
    UCModes = "uc_modes_copy",
    UCLab = "uc_lab_copy",
  })[target.Name]
  if not file then
    error("shim require: unknown instance " .. tostring(target.Name))
  end
  return require("./" .. file)
end
function M.get(name)
  if not registry[name] then
    registry[name] = M.require(mods[name])
  end
  return registry[name]
end
return M
EOF

header() {
  printf 'local __sh = require("./uc_shim")\n'
  printf 'local game = __sh.game\n'
  printf 'local script = __sh.scriptFor("%s")\n' "$1"
  printf 'local require = __sh.require\n'
  printf 'local Color3 = __sh.Color3\n'
  printf 'local Enum = __sh.Enum\n'
  printf 'local task = __sh.task\n'
  printf '\n'
}

while read -r m out; do
  case "$m" in
    UCConfig) SRC="$S/shared/$m.lua" ;;
    *) SRC="$S/server/UCModules/$m.lua" ;;
  esac
  { header "$m"; cat "$SRC"; } > "$WORK/$out"
done <<'MODS'
UCConfig uc_config_copy.lua
UCRng uc_rng_copy.lua
UCSimCore uc_simcore_copy.lua
UCModes uc_modes_copy.lua
UCLab uc_lab_copy.lua
MODS

cp "$ROOT/tools/luau_sim_tests.lua" "$WORK/tests.lua"
cd "$WORK"
"$LUAU" tests.lua
