--[[
	BEASTBOUND — GitHub -> Roblox Studio loader
	============================================
	Pulls every .lua file in src/ straight from GitHub and rebuilds the
	script tree inside an open Roblox Studio place. No Rojo needed.

	HOW TO USE
	1. Open any place in Roblox Studio (an empty Baseplate is fine).
	2. Enable HTTP: File > Game Settings > Security > "Allow HTTP Requests" > On.
	3. Open the Command Bar (View > Command Bar), open this file in a text
	   editor, copy EVERYTHING, paste it into the Command Bar and press Enter.
	4. Watch the Output window (View > Output). When it prints "DONE",
	   press Play to run the game.

	Notes
	- Re-running the loader refreshes the scripts to the latest GitHub state
	  (existing instances with the same name and class are replaced).
	- The mapping below mirrors default.project.json in the repository root.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")

local REPO = "remonmansour22-commits/tut"
local BRANCH = "main"
local RAW = ("https://raw.githubusercontent.com/%s/%s/"):format(REPO, BRANCH)
local TREE_API = ("https://api.github.com/repos/%s/git/trees/%s?recursive=1"):format(REPO, BRANCH)

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
	if path:sub(1, #"src/shared/") == "src/shared/" then
		return ensureFolder(ReplicatedStorage, "BeastboundShared"), path:sub(#"src/shared/" + 1)
	elseif path:sub(1, #"src/server/") == "src/server/" then
		local rel = path:sub(#"src/server/" + 1)
		local dir = rel:match("^(.+)/[^/]+$")
		if dir then
			local parent = ensureFolder(ServerScriptService, "BeastboundModules")
			for segment in dir:gmatch("[^/]+") do
				parent = ensureFolder(parent, segment)
			end
			return parent, rel:match("([^/]+)$")
		end
		return ServerScriptService, rel
	elseif path:sub(1, #"src/client/") == "src/client/" then
		return StarterPlayerScripts, path:sub(#"src/client/" + 1)
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
	local res = HttpService:GetAsync(TREE_API)
	local tree = HttpService:JSONDecode(res)

	local files = {}
	for _, item in ipairs(tree.tree) do
		if item.type == "blob" and item.path:match("^src/.+%.lua$") then
			table.insert(files, item.path)
		end
	end
	table.sort(files)

	if #files == 0 then
		error("No .lua files found under src/ in " .. REPO .. "@" .. BRANCH)
	end

	for _, path in ipairs(files) do
		local parent, name = parentFor(path)
		if parent then
			local source = HttpService:GetAsync(RAW .. path)
			local inst = ensureInstance(parent, instanceNameFor(path), classNameFor(path))
			inst.Source = source
			print(("[loader] %s -> %s/%s (%s)"):format(path, parent:GetFullName(), inst.Name, classNameFor(path)))
		end
	end

	print(("DONE — %d scripts loaded from %s@%s. Press Play to test."):format(#files, REPO, BRANCH))
end)

if not ok then
	warn("[loader] FAILED: " .. tostring(err))
end
