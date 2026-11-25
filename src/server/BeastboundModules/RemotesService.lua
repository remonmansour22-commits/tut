-- Path: ServerScriptService/BeastboundModules/RemotesService
-- Creates remotes at startup and provides the only sanctioned push paths
-- (personal snapshots, world snapshots, toasts). All client->server traffic
-- belongs to specific gameplay services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("BeastboundShared")
local Net = require(Shared.Net)

local RemotesService = {}

local NAMES = { "PlayerSync", "WorldSync", "Toast", "BuildRequest" }

function RemotesService.init()
	for _, name in ipairs(NAMES) do
		Net.get(name)
	end
end

function RemotesService.remote(name)
	return Net.get(name)
end

function RemotesService.playerSync(player, snapshot)
	Net.get("PlayerSync"):FireClient(player, snapshot)
end

function RemotesService.worldBroadcast(snapshot)
	Net.get("WorldSync"):FireAllClients(snapshot)
end

function RemotesService.toast(player, title, message, kind)
	Net.get("Toast"):FireClient(player, {
		title = title,
		message = message,
		kind = kind or "info",
	})
end

function RemotesService.toastAll(title, message, kind)
	Net.get("Toast"):FireAllClients({
		title = title,
		message = message,
		kind = kind or "info",
	})
end

return RemotesService
