-- Path: ReplicatedStorage/BeastboundShared/Net
-- Single source of truth for remote objects.
-- Server: creates missing remotes on demand. Client: waits for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NET_FOLDER_NAME = "BeastboundRemotes"

local Net = {}

local function getFolder()
	local folder = ReplicatedStorage:FindFirstChild(NET_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = NET_FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	return folder
end

local function createRemoteClass(name: string): string
	if name:sub(-2) == "Fn" then
		return "RemoteFunction"
	end
	return "RemoteEvent"
end

function Net.get(name: string): any
	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if remote then
		return remote
	end

	local isServer = game:GetService("RunService"):IsServer()
	if isServer then
		remote = Instance.new(createRemoteClass(name))
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	return folder:WaitForChild(name)
end

return Net
