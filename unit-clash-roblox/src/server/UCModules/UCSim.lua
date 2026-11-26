-- UNIT CLASH - server-authoritative battle simulation.
-- Kinematic units, brain-driven AI, projectiles, devices, auras, statuses.
-- The sim never touches client UI; the bootstrap wires results to remotes.

local RunService = game:GetService("RunService")
local UCConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("UCShared"):WaitForChild("UCConfig"))
local UCVisuals = require(script.Parent:WaitForChild("UCVisuals"))

local UCSim = {}
UCSim.__index = UCSim

local THINK_INTERVAL = 0.25
local FLEE_DURATION = 3
local BRAVE_DURATION = 4
local FLEE_SPEED_FACTOR = 0.85

function UCSim.new(unitsFolder)
	local self = setmetatable({}, UCSim)
	self.unitsFolder = unitsFolder
	self.phase = "setup"
	self.units = {}
	self.devices = {}
	self.projectiles = {}
	self.time = 0
	self.speed = 1
	self.paused = false
	self.spent = { A = 0, B = 0 }
	self.deployed = { A = 0, B = 0 }
	self.nextId = 1
	self.stats = {
		damage = { A = 0, B = 0 },
		healing = { A = 0, B = 0 },
		abilities = { A = 0, B = 0 },
	}
	self.outcome = nil
	self.accumulator = 0
	self.connection = nil
	return self
end

function UCSim:isSetup()
	return self.phase == "setup"
end

-- ---------- placement ----------

function UCSim:canPlace(team, unitId)
	local def = UCConfig.get(unitId)
	if not def or not UCConfig.TEAMS[team] then
		return false, "Unknown unit"
	end
	if self.phase ~= "setup" then
		return false, "Battle already started"
	end
	if self.spent[team] + def.cost > UCConfig.BUDGET[team] then
		return false, "Not enough budget"
	end
	if self.deployed[team] >= UCConfig.UNIT_LIMIT then
		return false, "Unit limit reached"
	end
	return true, nil
end

function UCSim:placeUnit(team, unitId, x, z)
	local ok, err = self:canPlace(team, unitId)
	if not ok then
		return false, err
	end
	local def = UCConfig.get(unitId)
	local position = Vector3.new(x, UCConfig.ARENA.BASE_Y + UCConfig.ARENA.UNIT_Y + def.radius, z)
	local unit = {
		id = self.nextId,
		def = def,
		team = team,
		hp = def.hp,
		maxHp = def.hp,
		pos = position,
		moveTarget = position,
		attackTarget = nil,
		attackCd = 0,
		abilityCd = 0,
		alive = true,
		slowUntil = 0,
		fleeTimer = 0,
		braveTimer = 0,
		fleeing = false,
		disengageTimer = 0,
		thinkTimer = 0,
		bounces = 0,
	}
	unit.model = UCVisuals.createUnitModel(def, team, position, self.unitsFolder)
	table.insert(self.units, unit)
	self.spent[team] = self.spent[team] + def.cost
	self.deployed[team] = self.deployed[team] + 1
	self.nextId = self.nextId + 1
	return true, nil
end

function UCSim:removeUnitAt(team, x, z)
	if self.phase ~= "setup" then
		return false, "Battle already started"
	end
	local best, bestDist = nil, 6
	for _, u in ipairs(self.units) do
		if u.team == team and u.alive then
			local d = (u.pos - Vector3.new(x, u.pos.Y, z)).Magnitude
			if d < bestDist then
				best, bestDist = u, d
			end
		end
	end
	if not best then
		return false, "No unit there"
	end
	self.spent[team] = self.spent[team] - best.def.cost
	self.deployed[team] = self.deployed[team] - 1
	best.model:Destroy()
	table.remove(self.units, table.find(self.units, best))
	return true, nil
end

-- ---------- helpers ----------

function UCSim:aliveOf(team)
	local n = 0
	for _, u in ipairs(self.units) do
		if u.alive and u.team == team then
			n = n + 1
		end
	end
	return n
end

function UCSim:nearestEnemy(u, maxDist)
	local best, bestDist = nil, maxDist or math.huge
	for _, e in ipairs(self.units) do
		if e.alive and e.team ~= u.team then
			local d = (e.pos - u.pos).Magnitude
			if d < bestDist then
				best, bestDist = e, d
			end
		end
	end
	return best, bestDist
end

function UCSim:woundedAlly(u, radius)
	local best, bestFrac = nil, 1
	for _, a in ipairs(self.units) do
		if a.alive and a.team == u.team and a ~= u then
			local frac = a.hp / a.maxHp
			if frac < bestFrac and (a.pos - u.pos).Magnitude <= radius then
				best, bestFrac = a, frac
			end
		end
	end
	return best
end

function UCSim:hasProtectAura(u)
	for _, a in ipairs(self.units) do
		if a.alive and a.team == u.team and a.def.aura and a.def.aura.kind == "protect" then
			if (a.pos - u.pos).Magnitude <= a.def.aura.radius then
				return true
			end
		end
	end
	return false
end

function UCSim:mightBonus(u)
	for _, a in ipairs(self.units) do
		if a.alive and a.team == u.team and a.def.aura and a.def.aura.kind == "might" then
			if (a.pos - u.pos).Magnitude <= a.def.aura.radius then
				return a.def.aura.bonus
			end
		end
	end
	return 0
end

function UCSim:effectiveSpeed(u)
	local speed = u.def.speed
	if u.fleeing then
		speed = speed * FLEE_SPEED_FACTOR
	end
	if self.time < u.slowUntil then
		speed = speed * 0.5
	end
	return speed
end

-- ---------- combat ----------

function UCSim:damage(attacker, target, amount, opts)
	if not target.alive then
		return
	end
	local opts = opts or {}
	local mitigated = amount * (1 - (target.def.armor or 0))
	if self:hasProtectAura(target) then
		mitigated = mitigated * 0.75
	end
	target.hp = target.hp - mitigated
	if attacker then
		self.stats.damage[attacker.team] = self.stats.damage[attacker.team] + mitigated
		if attacker.def.lifesteal then
			self:heal(attacker, attacker, mitigated * attacker.def.lifesteal)
		end
	end
	UCVisuals.hitFlash(target.model)
	UCVisuals.floatText(target.pos, "-" .. math.floor(mitigated), Color3.fromRGB(255, 120, 120))
	if opts.knockback then
		local dir = (target.pos - (opts.from or target.pos))
		if dir.Magnitude > 0.01 then
			target.pos = target.pos + dir.Unit * opts.knockback
			target.pos = Vector3.new(
				math.clamp(target.pos.X, -UCConfig.ARENA.HALF + 4, UCConfig.ARENA.HALF - 4),
				target.pos.Y,
				math.clamp(target.pos.Z, -UCConfig.ARENA.DEPTH + 4, UCConfig.ARENA.DEPTH - 4))
		end
	end
	if target.hp <= 0 then
		self:kill(attacker, target)
	else
		UCVisuals.updateHealth(target.model, target.hp, target.maxHp)
	end
end

function UCSim:heal(source, target, amount)
	if not target.alive or target.hp >= target.maxHp then
		return
	end
	local applied = math.min(amount, target.maxHp - target.hp)
	target.hp = target.hp + applied
	self.stats.healing[source.team] = self.stats.healing[source.team] + applied
	UCVisuals.updateHealth(target.model, target.hp, target.maxHp)
	UCVisuals.floatText(target.pos, "+" .. math.floor(applied), Color3.fromRGB(120, 255, 160))
end

function UCSim:kill(attacker, target)
	if not target.alive then
		return
	end
	local rebirth = target.def.rebirth
	if rebirth and not target.rebirthUsed then
		target.rebirthUsed = true
		target.hp = target.maxHp * rebirth.hpFrac
		UCVisuals.updateHealth(target.model, target.hp, target.maxHp)
		UCVisuals.ringEffect(target.pos, rebirth.novaRadius, target.def.color)
		UCVisuals.floatText(target.pos, "REBIRTH!", Color3.fromRGB(255, 190, 90))
		for _, e in ipairs(self.units) do
			if e.alive and e.team ~= target.team and (e.pos - target.pos).Magnitude <= rebirth.novaRadius then
				self:damage(target, e, rebirth.novaDamage)
			end
		end
		return
	end
	target.alive = false
	UCVisuals.deathBurst(target.model, target.def.color)
end

function UCSim:fireProjectile(shooter, target, damage)
	if not shooter.def.projectile then
		self:damage(shooter, target, damage, { from = shooter.pos })
		return
	end
	local part = UCVisuals.projectilePart(shooter.def.projectile, shooter.pos)
	part.Parent = workspace
	table.insert(self.projectiles, {
		part = part,
		pos = shooter.pos,
		target = target,
		speed = shooter.def.projectile.speed,
		damage = damage,
		team = shooter.team,
		shooter = shooter,
	})
end

function UCSim:stepProjectiles(dt)
	for i = #self.projectiles, 1, -1 do
		local p = self.projectiles[i]
		if not p.target.alive then
			p.part:Destroy()
			table.remove(self.projectiles, i)
		else
			local toTarget = p.target.pos - p.pos
			local step = p.speed * dt
			if toTarget.Magnitude <= step + p.target.def.radius then
				self:damage(p.shooter, p.target, p.damage, { from = p.pos })
				p.part:Destroy()
				table.remove(self.projectiles, i)
			else
				p.pos = p.pos + toTarget.Unit * step
				p.part.CFrame = CFrame.new(p.pos)
			end
		end
	end
end

-- ---------- abilities ----------

function UCSim:castAbility(u, target)
	local ab = u.def.ability
	if not ab or u.abilityCd > 0 then
		return
	end
	self.stats.abilities[u.team] = self.stats.abilities[u.team] + 1
	u.abilityCd = ab.cooldown
	if ab.kind == "heal" then
		local ally = self:woundedAlly(u, u.def.range)
		if ally then
			self:heal(u, ally, ab.amount)
			UCVisuals.ringEffect(ally.pos, 4, Color3.fromRGB(120, 255, 160))
		end
	elseif ab.kind == "slow_aoe" then
		UCVisuals.ringEffect(u.pos, ab.radius, Color3.fromRGB(200, 120, 255))
		for _, e in ipairs(self.units) do
			if e.alive and e.team ~= u.team and (e.pos - u.pos).Magnitude <= ab.radius then
				e.slowUntil = self.time + ab.duration
			end
		end
	elseif ab.kind == "slam_aoe" then
		local enemies = 0
		for _, e in ipairs(self.units) do
			if e.alive and e.team ~= u.team and (e.pos - u.pos).Magnitude <= ab.radius then
				enemies = enemies + 1
			end
		end
		if enemies >= 2 then
			UCVisuals.ringEffect(u.pos, ab.radius, Color3.fromRGB(255, 200, 100))
			for _, e in ipairs(self.units) do
				if e.alive and e.team ~= u.team and (e.pos - u.pos).Magnitude <= ab.radius then
					self:damage(u, e, ab.damage, { from = u.pos, knockback = ab.knockback })
				end
			end
		else
			u.abilityCd = 1
		end
	elseif ab.kind == "deploy_turret" then
		local enemy = self:nearestEnemy(u, u.def.range + 15)
		if enemy then
			local model = UCVisuals.turretModel(u.pos, UCConfig.TEAMS[u.team].color)
			table.insert(self.devices, {
				kind = "turret", team = u.team, model = model, pos = Vector3.new(u.pos.X, u.pos.Y, u.pos.Z),
				hp = ab.hp, damage = ab.damage, range = ab.range, cooldown = ab.cooldown2,
				cd = 0, expires = self.time + ab.lifetime,
			})
		else
			u.abilityCd = 1
		end
	elseif ab.kind == "deploy_pad" then
		local ally = self:woundedAlly(u, u.def.range + 10)
		if ally then
			local model = UCVisuals.padModel(ally.pos, ab.radius)
			table.insert(self.devices, {
				kind = "pad", team = u.team, model = model, pos = ally.pos,
				heal = ab.heal, radius = ab.radius, expires = self.time + ab.lifetime, tickTimer = 0,
			})
		else
			u.abilityCd = 1
		end
	elseif ab.kind == "dash" then
		local enemy = self:nearestEnemy(u, ab.distance)
		if enemy and u.hp < u.maxHp * 0.6 then
			local dir = (u.pos - enemy.pos).Unit
			u.pos = enemy.pos + dir * (enemy.def.radius + u.def.radius + 1)
			UCVisuals.ringEffect(u.pos, 3, u.def.color)
		else
			u.abilityCd = 1
		end
	elseif ab.kind == "bounce" then
		local hit1 = target
		if hit1 and hit1.alive then
			self:fireProjectile(u, hit1, u.def.damage)
			local jumped = 0
			for _, e in ipairs(self.units) do
				if jumped < ab.jumps and e.alive and e.team ~= u.team and e ~= hit1 then
					if (e.pos - hit1.pos).Magnitude <= 14 then
						self:fireProjectile(u, e, u.def.damage * ab.falloff)
						jumped = jumped + 1
					end
				end
			end
		else
			u.abilityCd = 1
		end
	end
end

-- ---------- AI brains ----------

function UCSim:think(u)
	local enemy, dist = self:nearestEnemy(u, math.huge)

	if u.def.brain == "healer" or u.def.brain == "artificer" then
		local ally = self:woundedAlly(u, u.def.range)
		if enemy and dist < 12 then
			u.moveTarget = u.pos + (u.pos - enemy.pos).Unit * 20
			u.attackTarget = nil
		elseif ally and ally.hp < ally.maxHp * 0.9 then
			u.moveTarget = ally.pos
			self:castAbility(u, ally)
		else
			u.moveTarget = u.pos
		end
		return
	end

	if u.def.brain == "guardian" then
		local ally = self:woundedAlly(u, 30)
		if enemy and dist <= u.def.range then
			u.moveTarget = u.pos
			u.attackTarget = enemy
		elseif ally then
			u.moveTarget = ally.pos + (enemy and (ally.pos - enemy.pos).Unit * 6 or Vector3.new())
		elseif enemy then
			u.moveTarget = enemy.pos
			u.attackTarget = enemy
		end
		return
	end

	if u.def.brain == "commander" then
		if enemy and dist <= u.def.range then
			u.moveTarget = u.pos
			u.attackTarget = enemy
		elseif enemy then
			local centroid, n = Vector3.new(), 0
			for _, a in ipairs(self.units) do
				if a.alive and a.team == u.team and a ~= u and a.def.category ~= "Ranged" and a.def.category ~= "Support" then
					centroid = centroid + a.pos
					n = n + 1
				end
			end
			if n > 0 then
				u.moveTarget = centroid / n
			else
				u.moveTarget = enemy.pos
			end
		end
		return
	end

	if u.def.brain == "ranged" or u.def.brain == "caster" or u.def.brain == "disruptor" or u.def.brain == "engineer" then
		if enemy then
			if dist < u.def.range * 0.65 then
				u.moveTarget = u.pos + (u.pos - enemy.pos).Unit * 12
			elseif dist > u.def.range * 0.95 then
				u.moveTarget = enemy.pos
			else
				u.moveTarget = u.pos
			end
			u.attackTarget = dist <= u.def.range and enemy or nil
		end
		return
	end

	if u.def.brain == "skirmisher" then
		if enemy and dist <= u.def.range then
			u.attackTarget = enemy
			u.moveTarget = u.pos
			if u.fleeTimer <= 0 and u.braveTimer <= 0 and u.hp < u.maxHp * 0.35 then
				u.fleeTimer = FLEE_DURATION
				u.fleeing = true
				u.attackTarget = nil
			end
		elseif u.fleeing then
			u.moveTarget = Vector3.new(u.team == "A" and -UCConfig.ARENA.HALF + 10 or UCConfig.ARENA.HALF - 10, u.pos.Y, u.pos.Z)
		elseif enemy then
			u.moveTarget = enemy.pos
			u.attackTarget = enemy
		end
		return
	end

	if u.def.brain == "trickster" then
		self:castAbility(u, enemy)
		if enemy then
			u.moveTarget = enemy.pos
			u.attackTarget = dist <= u.def.range and enemy or nil
		end
		return
	end

	if u.def.brain == "titan" then
		if enemy then
			u.moveTarget = enemy.pos
			u.attackTarget = dist <= u.def.range and enemy or nil
			self:castAbility(u, enemy)
		end
		return
	end

	if enemy then
		u.moveTarget = enemy.pos
		u.attackTarget = dist <= u.def.range and enemy or nil
	end
end

-- ---------- stepping ----------

function UCSim:stepUnit(u, dt)
	if not u.alive then
		return
	end
	u.attackCd = math.max(0, u.attackCd - dt)
	u.abilityCd = math.max(0, u.abilityCd - dt)
	u.thinkTimer = u.thinkTimer - dt
	if u.thinkTimer <= 0 then
		u.thinkTimer = THINK_INTERVAL
		self:think(u)
	end
	if u.fleeing then
		u.fleeTimer = u.fleeTimer - dt
		if u.fleeTimer <= 0 then
			u.fleeing = false
			u.braveTimer = BRAVE_DURATION
		end
	elseif u.braveTimer > 0 then
		u.braveTimer = u.braveTimer - dt
	end

	local toTarget = u.moveTarget - u.pos
	if toTarget.Magnitude > 0.5 then
		u.pos = u.pos + toTarget.Unit * self:effectiveSpeed(u) * dt
	end

	local target = u.attackTarget
	if target and target.alive and (target.pos - u.pos).Magnitude <= u.def.range + target.def.radius then
		if u.attackCd <= 0 and u.def.damage > 0 then
			u.attackCd = u.def.cooldown
			local dmg = u.def.damage * (1 + self:mightBonus(u))
			if u.def.ability and u.def.ability.kind == "bounce" then
				self:castAbility(u, target)
			else
				self:fireProjectile(u, target, dmg)
			end
		end
	end
end

function UCSim:separate()
	for i = 1, #self.units do
		local a = self.units[i]
		if a.alive then
			for j = i + 1, #self.units do
				local b = self.units[j]
				if b.alive then
					local offset = b.pos - a.pos
					local minDist = a.def.radius + b.def.radius
					local d = offset.Magnitude
					if d < minDist and d > 0.01 then
						local push = (minDist - d) * 0.5
						local dir = offset.Unit
						a.pos = a.pos - dir * push
						b.pos = b.pos + dir * push
					end
				end
			end
		end
	end
end

function UCSim:stepDevices(dt)
	for i = #self.devices, 1, -1 do
		local d = self.devices[i]
		if self.time >= d.expires then
			d.model:Destroy()
			table.remove(self.devices, i)
		elseif d.kind == "turret" then
			d.cd = math.max(0, d.cd - dt)
			if d.cd <= 0 then
				local best, bestDist = nil, d.range
				for _, e in ipairs(self.units) do
					if e.alive and e.team ~= d.team then
						local dist = (e.pos - d.pos).Magnitude
						if dist < bestDist then
							best, bestDist = e, dist
						end
					end
				end
				if best then
					d.cd = d.cooldown
					local part = UCVisuals.projectilePart({ color = UCConfig.TEAMS[d.team].color }, d.pos)
					part.Parent = workspace
					table.insert(self.projectiles, {
						part = part, pos = d.pos, target = best, speed = 60,
						damage = d.damage, team = d.team, shooter = nil,
					})
				end
			end
		elseif d.kind == "pad" then
			d.tickTimer = d.tickTimer - dt
			if d.tickTimer <= 0 then
				d.tickTimer = 1
				for _, a in ipairs(self.units) do
					if a.alive and a.team == d.team and (a.pos - d.pos).Magnitude <= d.radius then
						self:heal(d, a, d.heal)
					end
				end
			end
		end
	end
end

function UCSim:step(dt)
	self.time = self.time + dt
	for _, u in ipairs(self.units) do
		self:stepUnit(u, dt)
	end
	self:separate()
	self:stepProjectiles(dt)
	self:stepDevices(dt)
	for _, u in ipairs(self.units) do
		if u.alive and u.model and u.model.Parent then
			u.model:PivotTo(CFrame.new(u.pos))
		end
	end
	self:checkVictory()
end

function UCSim:score(team)
	local s = 0
	for _, u in ipairs(self.units) do
		if u.alive and u.team == team then
			s = s + u.def.cost * (u.hp / u.maxHp)
		end
	end
	return s
end

function UCSim:checkVictory()
	if self.outcome then
		return
	end
	local a, b = self:aliveOf("A"), self:aliveOf("B")
	if a == 0 or b == 0 then
		local winner = (a == 0 and b == 0) and "draw" or (a > 0 and "A" or "B")
		self.outcome = { winner = winner, reason = "annihilation", duration = self.time }
	elseif self.time >= UCConfig.BATTLE_TIME_LIMIT then
		local sa, sb = self:score("A"), self:score("B")
		local winner = math.abs(sa - sb) / math.max(1, sa + sb) < 0.02 and "draw" or (sa > sb and "A" or "B")
		self.outcome = { winner = winner, reason = "timeout", duration = self.time }
	end
	if self.outcome then
		self.phase = "results"
		if self.connection then
			self.connection:Disconnect()
			self.connection = nil
		end
	end
end

function UCSim:startBattle()
	if self.phase ~= "setup" or self.connection then
		return
	end
	self.phase = "battle"
	self.connection = RunService.Heartbeat:Connect(function(dt)
		if self.paused or self.outcome then
			return
		end
		self.accumulator = self.accumulator + dt * self.speed
		local stepTime = 1 / UCConfig.TICK_RATE
		while self.accumulator >= stepTime and not self.outcome do
			self.accumulator = self.accumulator - stepTime
			self:step(stepTime)
		end
	end)
end

function UCSim:results()
	local function teamResult(team)
		local survivors = 0
		for _, u in ipairs(self.units) do
			if u.alive and u.team == team then
				survivors = survivors + 1
			end
		end
		return {
			deployed = self.deployed[team],
			survivors = survivors,
			damage = math.floor(self.stats.damage[team]),
			healing = math.floor(self.stats.healing[team]),
			abilities = self.stats.abilities[team],
			spent = self.spent[team],
		}
	end
	return {
		winner = self.outcome and self.outcome.winner or "draw",
		reason = self.outcome and self.outcome.reason or "timeout",
		duration = math.floor(self.time),
		A = teamResult("A"),
		B = teamResult("B"),
	}
end

function UCSim:reset()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	for _, u in ipairs(self.units) do
		if u.model then
			u.model:Destroy()
		end
	end
	for _, d in ipairs(self.devices) do
		d.model:Destroy()
	end
	for _, p in ipairs(self.projectiles) do
		p.part:Destroy()
	end
	self.units = {}
	self.devices = {}
	self.projectiles = {}
	self.spent = { A = 0, B = 0 }
	self.deployed = { A = 0, B = 0 }
	self.stats = { damage = { A = 0, B = 0 }, healing = { A = 0, B = 0 }, abilities = { A = 0, B = 0 } }
	self.time = 0
	self.accumulator = 0
	self.outcome = nil
	self.paused = false
	self.phase = "setup"
end

return UCSim
