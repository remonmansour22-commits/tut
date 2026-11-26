-- UNIT CLASH - presenter. Reads sim-core state + events, mirrors them into
-- workspace Instances. Never mutates core state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UCConfig = require(ReplicatedStorage:WaitForChild("UCShared"):WaitForChild("UCConfig"))
local UCVisuals = require(script.Parent:WaitForChild("UCVisuals"))

local UCPresenter = {}
UCPresenter.__index = UCPresenter

local function colorFor(name)
	if name == "orange" then
		return Color3.fromRGB(255, 150, 60)
	elseif name == "purple" then
		return Color3.fromRGB(200, 120, 255)
	elseif name == "pink" then
		return Color3.fromRGB(240, 130, 200)
	end
	return Color3.fromRGB(255, 255, 255)
end

function UCPresenter.new(core, unitsFolder)
	local self = setmetatable({}, UCPresenter)
	self.core = core
	self.folder = unitsFolder
	self.models = {}
	self.lastHp = {}
	return self
end

function UCPresenter:sync()
	for _, u in ipairs(self.core.units) do
		local model = self.models[u.id]
		if u.alive then
			if not model or not model.Parent then
				model = UCVisuals.createUnitModel(u.def, u.team, Vector3.new(u.x, u.def.radius + 1, u.z), self.folder)
				self.models[u.id] = model
				self.lastHp[u.id] = u.hp
			else
				model:PivotTo(CFrame.new(Vector3.new(u.x, u.def.radius + 1, u.z)))
			end
			if self.lastHp[u.id] ~= u.hp then
				UCVisuals.updateHealth(model, u.hp, u.maxHp)
				self.lastHp[u.id] = u.hp
			end
		elseif model and model.Parent then
			model:Destroy()
			self.models[u.id] = nil
		end
	end
end

function UCPresenter:handleEvents()
	for _, event in ipairs(self.core:drainEvents()) do
		local at = Vector3.new(event.x or 0, UCConfig.ARENA.BASE_Y + 2, event.z or 0)
		if event.type == "hit" then
			UCVisuals.floatText(at, "-" .. event.amount, Color3.fromRGB(255, 120, 120))
		elseif event.type == "heal" then
			UCVisuals.floatText(at, "+" .. event.amount, Color3.fromRGB(120, 255, 160))
			UCVisuals.ringEffect(at, 3, Color3.fromRGB(120, 255, 160))
		elseif event.type == "death" then
			local model = event.id and self.models[event.id]
			if model then
				local c = event.color
				UCVisuals.deathBurst(model, c and Color3.new(c[1], c[2], c[3]) or Color3.fromRGB(255, 255, 255))
				self.models[event.id] = nil
			end
		elseif event.type == "rebirth" then
			UCVisuals.ringEffect(at, event.r or 20, Color3.fromRGB(255, 150, 60))
			UCVisuals.floatText(at, "REBIRTH!", Color3.fromRGB(255, 190, 90))
		elseif event.type == "ring" then
			UCVisuals.ringEffect(at, event.r or 10, colorFor(event.color))
		elseif event.type == "ability" then
			UCVisuals.floatText(at, event.name, UCConfig.TEAMS[event.team].color)
		elseif event.type == "turret" then
			UCVisuals.turretModel(at, UCConfig.TEAMS[event.team].color)
		elseif event.type == "pad" then
			UCVisuals.padModel(at, event.r or 14)
		end
	end
end

function UCPresenter:momentum()
	local mA, mB = 0, 0
	for _, u in ipairs(self.core.units) do
		if u.alive then
			local value = u.def.cost * (u.hp / u.maxHp)
			if u.team == "A" then
				mA = mA + value
			else
				mB = mB + value
			end
		end
	end
	return { A = mA, B = mB }
end

function UCPresenter:destroyAll()
	for id, model in pairs(self.models) do
		if model.Parent then
			model:Destroy()
		end
		self.models[id] = nil
	end
end

return UCPresenter
