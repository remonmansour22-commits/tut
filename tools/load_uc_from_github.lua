--[[
	UNIT CLASH (Roblox) - GitHub -> Studio loader
	==============================================
	Pulls every .lua file under unit-clash-roblox/src/ from GitHub and rebuilds
	the game inside an open Studio place. No Rojo needed.

	HOW TO USE
	1. Open any place in Roblox Studio (empty Baseplate is fine).
	2. Game Settings > Security > "Allow HTTP Requests" > On.
	3. Copy this ENTIRE file into the Command Bar (View > Command Bar), press Enter.
	4. Output prints "DONE" -> press Play. Pick a unit, click a half, START.

	Re-run it any time to refresh to the latest GitHub version.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")

local REPO = "remonmansour22-commits/tut"
local ROOT = "unit-clash-roblox/"
-- Primary branch first, fallback to the development (PR) branch.
local BRANCHES = { "main", "vibe/unit-clash-f886b5" }
local BRANCH, RAW, TREE_API

local function pickBranch()
	for _, b in ipairs(BRANCHES) do
		local url = ("https://api.github.com/repos/%s/git/trees/%s?recursive=1"):format(REPO, b)
		local tree = HttpService:JSONDecode(HttpService:GetAsync(url))
		local count = 0
		for _, item in ipairs(tree.tree) do
			if item.type == "blob" and item.path:sub(1, #ROOT) == ROOT and item.path:match("%.lua$") then
				count = count + 1
			end
		end
		if count > 0 then
			BRANCH = b
			RAW = ("https://raw.githubusercontent.com/%s/%s/"):format(REPO, b)
			TREE_API = url
			return tree
		end
	end
	error("No .lua files under " .. ROOT .. " found on any known branch of " .. REPO)
end

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function classNameFor(path)
	if path:match("%.server%.lua$") then
		return "Script"
	elseif path:match("%.client%.lua$") then
		return "LocalScript"
	end
	return "ModuleScript"
end

local function instanceNameFor(path)
	local name = path:match("([^/]+)$")
	name = name:gsub("%.server%.lua$", ""):gsub("%.client%.lua$", ""):gsub("%.lua$", "")
	return name
end

local function parentFor(path)
	local rel = path:sub(#ROOT + 1)
	if rel:sub(1, #"src/shared/") == "src/shared/" then
		return ensureFolder(ReplicatedStorage, "UCShared"), rel:sub(#"src/shared/" + 1)
	elseif rel:sub(1, #"src/server/UCModules/") == "src/server/UCModules/" then
		return ensureFolder(ServerScriptService, "UCModules"), rel:sub(#"src/server/UCModules/" + 1)
	elseif rel:sub(1, #"src/server/") == "src/server/" then
		return ServerScriptService, rel:sub(#"src/server/" + 1)
	elseif rel:sub(1, #"src/client/") == "src/client/" then
		return StarterPlayerScripts, rel:sub(#"src/client/" + 1)
	end
	return nil, nil
end

local function ensureInstance(parent, name, className)
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing.ClassName == className then
			return existing
		end
		existing:Destroy()
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

local ok, err = pcall(function()
	local tree = pickBranch()
	local files = {}
	for _, item in ipairs(tree.tree) do
		if item.type == "blob" and item.path:sub(1, #ROOT) == ROOT and item.path:match("%.lua$") then
			table.insert(files, item.path)
		end
	end
	table.sort(files)
	if #files == 0 then
		error("No .lua files found under " .. ROOT .. " in " .. REPO .. "@" .. BRANCH)
	end
	for _, path in ipairs(files) do
		local parent, name = parentFor(path)
		if parent then
			local source = HttpService:GetAsync(RAW .. path)
			local inst = ensureInstance(parent, instanceNameFor(path), classNameFor(path))
			inst.Source = source
			print(("[UC loader] %s -> %s/%s (%s)"):format(path, parent:GetFullName(), inst.Name, classNameFor(path)))
		end
	end
	print(("DONE - %d scripts loaded from %s@%s. Press Play to play UNIT CLASH."):format(#files, REPO, BRANCH))
end)

if not ok then
	warn("[UC loader] FAILED: " .. tostring(err))
end
