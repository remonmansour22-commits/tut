-- UNIT CLASH - share codes. Config <-> compact portable string.
-- Format: "UC1." + base64(JSON). Shared module: works on server and client.

local HttpService = game:GetService("HttpService")

local UCShareCodec = {}

function UCShareCodec.encode(config)
	local ok, encoded = pcall(function()
		return "UC1." .. HttpService:Base64Encode(HttpService:JSONEncode(config))
	end)
	if ok then
		return encoded
	end
	return nil
end

function UCShareCodec.decode(code)
	if type(code) ~= "string" or code:sub(1, 4) ~= "UC1." then
		return nil
	end
	local ok, config = pcall(function()
		return HttpService:JSONDecode(HttpService:Base64Decode(code:sub(5)))
	end)
	if ok and type(config) == "table" and type(config.teams) == "table" then
		return config
	end
	return nil
end

return UCShareCodec
