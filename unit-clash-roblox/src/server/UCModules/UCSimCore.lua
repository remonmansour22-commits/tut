-- UNIT CLASH - headless deterministic battle core.
-- Pure data: no Instances, no rendering. Fixed 30 Hz tick, seeded RNG, event
-- queue consumed by the presenter (live battle) or ignored (Battle Lab runs).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UCConfig = require(ReplicatedStorage:WaitForChild("UCShared"):WaitForChild("UCConfig"))
local UCRng = require(script.Parent:WaitForChild("UCRng"))

local UCSimCore = {}
UCSimCore.__index = UCSimCore

local TICK = 1 / 30
local THINK_INTERVAL = 0.25
local FLEE_DURATION = 3
local BRAVE_DURATION = 4
local FLEE_SPEED = 0.85

local function mod(list, key)
	local o = {}
	if list then
		for _, m in ipairs(list) do
			o[m] = true
		end
	end
	if key then
		o[key] = true
	end
	return o
end

local function cloneDef(unitId, upgradeId, factionId)
	local def = UCConfig.get(unitId)
	if not def then
		return nil
	end
	local d = table.clone(def)
	if d.ability then
		d.ability = table.clone(d.ability)
	end
	if d.projectile then
		d.projectile = table.clone(d.projectile)
	end
	if d.aura then
		d.aura = table.clone(d.aura)
	end
	if d.rebirth then
		d.rebirth = table.clone(d.rebirth)
	end
	local up = upgradeId and UCConfig.UPGRADES[upgradeId]
	if up and up.unit == unitId and up.apply then
		up.apply(d)
	end
	local fac = factionId and UCConfig.FACTIONS[factionId]
	if fac then
		fac.apply(d)
	end
	return d
end

function UCSimCore.new(config)
	local self = setmetatable({}, UCSimCore)
	self.config = config
	self.arenaId = config.arena or "grassland"
	local arena = UCConfig.ARENAS[self.arenaId] or UCConfig.ARENAS.grassland
	self.modifiers = mod(arena.modifiers)
	if config.modifiers then
		for m in pairs(config.modifiers) do
			self.modifiers[m] = true
		end
	end
	self.timeLimit = config.timeLimit or UCConfig.BATTLE_TIME_LIMIT
	self.rng = UCRng.new(config.seed or 1)
	self.units = {}
	self.devices = {}
	self.projectiles = {}
	self.events = {}
	self.stats = { damage = { A = 0, B = 0 }, healing = { A = 0, B = 0 }, abilities = { A = 0, B = 0 }, devices = { A = 0, B = 0 } }
	self.regen = {
		A = config.factions and config.factions.A == "wildgrove" or false,
		B = config.factions and config.factions.B == "wildgrove" or false,
	}
	self.timeline = {}
	self.t = 0
	self.outcome = nil
	self.nextId = 1
	self.timelineTimer = 0

	for team, list in pairs(config.teams or {}) do
		for _, entry in ipairs(list) do
			local def = cloneDef(entry.type, entry.upgrade, config.factions and config.factions[team])
			if def then
				local frac = entry.hpFrac or 1
				local unit = {
					id = self.nextId, type = entry.type, team = team, def = def,
					upgrade = entry.upgrade, hp = def.hp * frac, maxHp = def.hp,
					x = entry.x, z = entry.z, mx = entry.x, mz = entry.z,
					target = nil, attackCd = 0, abilityCd = 0, alive = true,
					rebirthUsed = false, slowUntil = 0, fleeing = false,
					fleeTimer = 0, braveTimer = 0, thinkTimer = self.rng:range(0, THINK_INTERVAL),
				}
				table.insert(self.units, unit)
				self.nextId = self.nextId + 1
			end
		end
	end
	return self
end

function UCSimCore:emit(event)
	event.t = self.t
	table.insert(self.events, event)
end

function UCSimCore:drainEvents()
	local e = self.events
	self.events = {}
	return e
end

function UCSimCore:aliveOf(team)
	local n = 0
	for _, u in ipairs(self.units) do
		if u.alive and u.team == team then
			n = n + 1
		end
	end
	return n
end

function UCSimCore:nearestEnemy(u)
	local best, bestDist = nil, math.huge
	for _, e in ipairs(self.units) do
		if e.alive and e.team ~= u.team then
			local d = (e.x - u.x) ^ 2 + (e.z - u.z) ^ 2
			if d < bestDist then
				best, bestDist = e, d
			end
		end
	end
	if best then
		return best, math.sqrt(bestDist)
	end
	return nil, math.huge
end

function UCSimCore:woundedAlly(u, radius)
	local best, bestFrac = nil, 1
	for _, a in ipairs(self.units) do
		if a.alive and a.team == u.team and a ~= u then
			local frac = a.hp / a.maxHp
			local d = (a.x - u.x) ^ 2 + (a.z - u.z) ^ 2
			if frac < bestFrac and d <= radius * radius then
				best, bestFrac = a, frac
			end
		end
	end
	return best
end

function UCSimCore:aura(u, kind)
	for _, a in ipairs(self.units) do
		if a.alive and a.team == u.team and a.def.aura and a.def.aura.kind == kind then
			local d = (a.x - u.x) ^ 2 + (a.z - u.z) ^ 2
			if d <= a.def.aura.radius * a.def.aura.radius then
				return a.def.aura
			end
		end
	end
	return nil
end

function UCSimCore:effectiveSpeed(u)
	local speed = u.def.speed
	if u.fleeing then
		speed = speed * FLEE_SPEED
	end
	if self.t < u.slowUntil then
		speed = speed * 0.5
	end
	if self.modifiers.slippery then
		speed = speed * 1.15
	end
	return speed
end

function UCSimCore:knockbackScale()
	if self.modifiers.lowgravity then
		return 2
	elseif self.modifiers.heavyknock then
		return 1.5
	elseif self.modifiers.slippery then
		return 1.3
	end
	return 1
end

function UCSimCore:clampPos(u)
	u.x = math.clamp(u.x, -98, 98)
	u.z = math.clamp(u.z, -28, 28)
end

function UCSimCore:damage(attacker, target, amount, opts)
	if not target.alive then
		return 0
	end
	local opts = opts or {}
	local mitigated = amount * (1 - (target.def.armor or 0))
	if self:aura(target, "protect") then
		mitigated = mitigated * 0.75
	end
	target.hp = target.hp - mitigated
	if attacker then
		self.stats.damage[attacker.team] = self.stats.damage[attacker.team] + mitigated
		if attacker.def.lifesteal then
			self:heal(attacker, attacker, mitigated * attacker.def.lifesteal)
		end
	end
	self:emit({ type = "hit", x = target.x, z = target.z, amount = math.floor(mitigated) })
	if opts.knockback then
		local dx, dz = target.x - (opts.fx or target.x), target.z - (opts.fz or target.z)
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 0.01 then
			local kb = opts.knockback * self:knockbackScale()
			target.x = target.x + dx / d * kb
			target.z = target.z + dz / d * kb
			self:clampPos(target)
		end
	end
	if target.hp <= 0 then
		self:kill(attacker, target)
	else
		if attacker and attacker.upgrade == "reaper_deathwing" and target.hp < target.maxHp * 0.35 then
			target.hp = target.hp - mitigated * 0.6
			if target.hp <= 0 then
				self:kill(attacker, target)
			end
		end
	end
	return mitigated
end

function UCSimCore:heal(source, target, amount)
	if not target.alive or target.hp >= target.maxHp then
		return
	end
	local applied = math.min(amount, target.maxHp - target.hp)
	target.hp = target.hp + applied
	self.stats.healing[source.team] = self.stats.healing[source.team] + applied
	self:emit({ type = "heal", x = target.x, z = target.z, amount = math.floor(applied) })
end

function UCSimCore:kill(attacker, target)
	if not target.alive then
		return
	end
	local rebirth = target.def.rebirth
	if rebirth and not target.rebirthUsed then
		target.rebirthUsed = true
		target.hp = target.maxHp * rebirth.hpFrac
		self:emit({ type = "rebirth", x = target.x, z = target.z, r = rebirth.novaRadius, color = "orange" })
		for _, e in ipairs(self.units) do
			if e.alive and e.team ~= target.team then
				local d = (e.x - target.x) ^ 2 + (e.z - target.z) ^ 2
				if d <= rebirth.novaRadius * rebirth.novaRadius then
					self:damage(target, e, rebirth.novaDamage, { fx = target.x, fz = target.z, knockback = 8 })
				end
			end
		end
		return
	end
	target.alive = false
	self:emit({
		type = "death", id = target.id, x = target.x, z = target.z, team = target.team,
		color = { target.def.color.R, target.def.color.G, target.def.color.B },
	})
end

function UCSimCore:fireProjectile(shooter, target, damage)
	self:emit({
		type = "shoot", fx = shooter.x, fz = shooter.z,
		tx = target.x, tz = target.z,
		speed = shooter.def.projectile and shooter.def.projectile.speed or 60,
		team = shooter.team,
	})
	if not shooter.def.projectile then
		self:damage(shooter, target, damage, { fx = shooter.x, fz = shooter.z })
		return
	end
	table.insert(self.projectiles, {
		x = shooter.x, z = shooter.z, target = target, shooter = shooter,
		speed = shooter.def.projectile.speed, damage = damage,
	})
end

function UCSimCore:damageDevice(attacker, device, amount)
	if not device or device.hp <= 0 or amount <= 0 then
		return
	end
	device.hp = math.max(0, device.hp - amount)
	local byTeam = attacker and attacker.team or (device.team == "A" and "B" or "A")
	self.stats.devices[byTeam] = self.stats.devices[byTeam] + amount
	if device.hp <= 0 then
		device.alive = false
		self:emit({ type = "deviceDown", x = device.x, z = device.z })
	end
end

function UCSimCore:damageDevices(attacker, x, z, r, dmg)
	for _, d in ipairs(self.devices) do
		if d.team ~= attacker.team and d.hp > 0 then
			local dd = math.sqrt((d.x - x) ^ 2 + (d.z - z) ^ 2)
			if dd <= r + 2 then
				self:damageDevice(attacker, d, dmg)
			end
		end
	end
end

function UCSimCore:stepProjectiles(dt)
	for i = #self.projectiles, 1, -1 do
		local p = self.projectiles[i]
		local tgt = p.target
		if not tgt.alive then
			table.remove(self.projectiles, i)
		else
			local dx, dz = tgt.x - p.x, tgt.z - p.z
			local dist = math.sqrt(dx * dx + dz * dz)
			local step = p.speed * dt
			if self.modifiers.wind then
				p.x = p.x + math.cos(self.t * 2) * 4 * dt
				p.z = p.z + math.sin(self.t * 3) * 4 * dt
			end
			local blocked = false
			if p.shooter then
				for _, d in ipairs(self.devices) do
					if d.team ~= p.shooter.team and d.hp > 0 then
						local dd = math.sqrt((d.x - p.x) ^ 2 + (d.z - p.z) ^ 2)
						if dd <= step + 2 then
							self:damageDevice(p.shooter, d, p.damage)
							blocked = true
							break
						end
					end
				end
			end
			if blocked then
				table.remove(self.projectiles, i)
			elseif dist <= step + tgt.def.radius then
				self:damage(p.shooter, tgt, p.damage, { fx = p.x, fz = p.z })
				table.remove(self.projectiles, i)
			else
				p.x = p.x + dx / dist * step
				p.z = p.z + dz / dist * step
			end
		end
	end
end

function UCSimCore:castAbility(u, target)
	local ab = u.def.ability
	if not ab or u.abilityCd > 0 then
		return
	end
	u.abilityCd = ab.cooldown
	self.stats.abilities[u.team] = self.stats.abilities[u.team] + 1
	self:emit({ type = "ability", x = u.x, z = u.z, name = ab.name, team = u.team })
	if ab.kind == "heal" then
		local ally = self:woundedAlly(u, u.def.range)
		if ally then
			self:heal(u, ally, ab.amount)
		end
	elseif ab.kind == "slow_aoe" then
		self:emit({ type = "ring", x = u.x, z = u.z, r = ab.radius, color = "purple" })
		for _, e in ipairs(self.units) do
			if e.alive and e.team ~= u.team then
				local d = (e.x - u.x) ^ 2 + (e.z - u.z) ^ 2
				if d <= ab.radius * ab.radius then
					e.slowUntil = self.t + ab.duration
				end
			end
		end
	elseif ab.kind == "slam_aoe" then
		local enemies = 0
		for _, e in ipairs(self.units) do
			if e.alive and e.team ~= u.team then
				local d = (e.x - u.x) ^ 2 + (e.z - u.z) ^ 2
				if d <= ab.radius * ab.radius then
					enemies = enemies + 1
				end
			end
		end
		if enemies >= 2 then
			self:emit({ type = "ring", x = u.x, z = u.z, r = ab.radius, color = "orange" })
			for _, e in ipairs(self.units) do
				if e.alive and e.team ~= u.team then
					local d = (e.x - u.x) ^ 2 + (e.z - u.z) ^ 2
					if d <= ab.radius * ab.radius then
						self:damage(u, e, ab.damage, { fx = u.x, fz = u.z, knockback = ab.knockback })
					end
				end
			end
			self:damageDevices(u, u.x, u.z, ab.radius, ab.damage)
		else
			u.abilityCd = 1
		end
	elseif ab.kind == "deploy_turret" then
		local enemy = self:nearestEnemy(u)
		if enemy and math.sqrt((enemy.x - u.x) ^ 2 + (enemy.z - u.z) ^ 2) <= u.def.range + 15 then
			table.insert(self.devices, {
				kind = "turret", isDevice = true, alive = true, team = u.team, x = u.x, z = u.z,
				hp = ab.hp, maxHp = ab.hp, damage = ab.damage, range = ab.range,
				cooldown = ab.cooldown2, cd = 0, expires = self.t + ab.lifetime,
				def = { radius = 1.2, name = "Turret" },
			})
			self:emit({ type = "turret", x = u.x, z = u.z, team = u.team })
		else
			u.abilityCd = 1
		end
	elseif ab.kind == "deploy_pad" then
		local ally = self:woundedAlly(u, u.def.range + 10)
		if ally then
			table.insert(self.devices, {
				kind = "pad", isDevice = true, alive = true, team = u.team, x = ally.x, z = ally.z,
				hp = ab.padHp or 50, maxHp = ab.padHp or 50,
				def = { radius = 1.2, name = "Repair Pad" },
				heal = ab.heal, radius = ab.radius, expires = self.t + ab.lifetime, tickTimer = 0,
			})
			self:emit({ type = "pad", x = ally.x, z = ally.z, r = ab.radius })
		else
			u.abilityCd = 1
		end
	elseif ab.kind == "dash" then
		local enemy = self:nearestEnemy(u)
		if enemy and math.sqrt((enemy.x - u.x) ^ 2 + (enemy.z - u.z) ^ 2) <= ab.distance and u.hp < u.maxHp * 0.6 then
			local dx, dz = u.x - enemy.x, u.z - enemy.z
			local d = math.max(0.01, math.sqrt(dx * dx + dz * dz))
			u.x = enemy.x + dx / d * (enemy.def.radius + u.def.radius + 1)
			u.z = enemy.z + dz / d * (enemy.def.radius + u.def.radius + 1)
			self:clampPos(u)
			self:emit({ type = "ring", x = u.x, z = u.z, r = 3, color = "pink" })
		else
			u.abilityCd = 1
		end
	elseif ab.kind == "bounce" and target and target.alive then
		self:fireProjectile(u, target, u.def.damage)
		local jumped = 0
		for _, e in ipairs(self.units) do
			if jumped < ab.jumps and e.alive and e.team ~= u.team and e ~= target then
				local d = (e.x - target.x) ^ 2 + (e.z - target.z) ^ 2
				if d <= 14 * 14 then
					self:fireProjectile(u, e, u.def.damage * ab.falloff)
					jumped = jumped + 1
				end
			end
		end
	end
end

-- ---------- brains ----------

function UCSimCore:thinkBrain(u)
	local enemy, dist = self:nearestEnemy(u)
	local brain = u.def.brain

	if brain == "healer" or brain == "artificer" then
		local ally = self:woundedAlly(u, u.def.range)
		if enemy and dist < 12 then
			u.mx = u.x + (u.x - enemy.x) / math.max(0.01, dist) * 20
			u.mz = u.z + (u.z - enemy.z) / math.max(0.01, dist) * 20
			u.target = nil
		elseif ally and ally.hp < ally.maxHp * 0.9 then
			u.mx, u.mz = ally.x, ally.z
			self:castAbility(u, ally)
		else
			u.mx, u.mz = u.x, u.z
		end
		return
	end

	if brain == "guardian" then
		local ally = self:woundedAlly(u, 30)
		if enemy and dist <= u.def.range then
			u.mx, u.mz = u.x, u.z
			u.target = enemy
		elseif ally then
			if enemy then
				local dx, dz = ally.x - enemy.x, ally.z - enemy.z
				local d = math.max(0.01, math.sqrt(dx * dx + dz * dz))
				u.mx = ally.x + dx / d * 6
				u.mz = ally.z + dz / d * 6
			else
				u.mx, u.mz = ally.x, ally.z
			end
		elseif enemy then
			u.mx, u.mz = enemy.x, enemy.z
			u.target = enemy
		end
		return
	end

	if brain == "commander" then
		if enemy and dist <= u.def.range then
			u.mx, u.mz = u.x, u.z
			u.target = enemy
		elseif enemy then
			local cx, cz, n = 0, 0, 0
			for _, a in ipairs(self.units) do
				if a.alive and a.team == u.team and a ~= u and a.def.category ~= "Ranged" and a.def.category ~= "Support" then
					cx, cz, n = cx + a.x, cz + a.z, n + 1
				end
			end
			if n > 0 then
				u.mx, u.mz = cx / n, cz / n
			else
				u.mx, u.mz = enemy.x, enemy.z
			end
		end
		return
	end

	if brain == "ranged" or brain == "caster" or brain == "disruptor" or brain == "engineer" then
		if enemy then
			if dist < u.def.range * 0.65 then
				u.mx = u.x + (u.x - enemy.x) / math.max(0.01, dist) * 12
				u.mz = u.z + (u.z - enemy.z) / math.max(0.01, dist) * 12
			elseif dist > u.def.range * 0.95 then
				u.mx, u.mz = enemy.x, enemy.z
			else
				u.mx, u.mz = u.x, u.z
			end
			u.target = dist <= u.def.range and enemy or nil
		end
		return
	end

	if brain == "skirmisher" then
		if enemy and dist <= u.def.range then
			u.target = enemy
			u.mx, u.mz = u.x, u.z
			if u.fleeTimer <= 0 and u.braveTimer <= 0 and u.hp < u.maxHp * 0.35 then
				u.fleeTimer = FLEE_DURATION
				u.fleeing = true
				u.target = nil
			end
		elseif u.fleeing then
			u.mx = u.team == "A" and -90 or 90
			u.mz = u.z
		elseif enemy then
			u.mx, u.mz = enemy.x, enemy.z
			u.target = enemy
		end
		return
	end

	if brain == "trickster" then
		self:castAbility(u, enemy)
		if enemy then
			u.mx, u.mz = enemy.x, enemy.z
			u.target = dist <= u.def.range and enemy or nil
		end
		return
	end

	if brain == "titan" then
		if enemy then
			u.mx, u.mz = enemy.x, enemy.z
			u.target = dist <= u.def.range and enemy or nil
			self:castAbility(u, enemy)
		end
		return
	end

	if enemy then
		u.mx, u.mz = enemy.x, enemy.z
		u.target = dist <= u.def.range and enemy or nil
	end
end

-- Counterplay: enemy turrets are priorities. In-range units attack without
-- repositioning; melee units walk to the turret. Pads only draw fire when
-- no unit target exists.
function UCSimCore:devicePriority(u)
	local dev, devDist = nil, math.huge
	for _, d in ipairs(self.devices) do
		if d.alive and d.hp > 0 and d.team ~= u.team then
			local dd = math.sqrt((d.x - u.x) ^ 2 + (d.z - u.z) ^ 2)
			if dd < devDist then
				dev, devDist = d, dd
			end
		end
	end
	if not dev then
		return
	end
	local inRange = devDist <= u.def.range + (dev.def.radius or 1.2)
	local melee = not u.def.projectile
	if dev.kind == "turret" and (inRange or melee) then
		u.target = dev
		u.mx, u.mz = dev.x, dev.z
	elseif dev.kind ~= "turret" and not u.target and inRange then
		u.target = dev
	end
end

function UCSimCore:think(u)
	self:thinkBrain(u)
	self:devicePriority(u)
end

-- ---------- stepping ----------

function UCSimCore:stepUnit(u, dt)
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
	if self.regen[u.team] then
		self:heal(u, u, 1 * dt)
	end

	local dx, dz = u.mx - u.x, u.mz - u.z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist > 0.5 then
		u.x = u.x + dx / dist * self:effectiveSpeed(u) * dt
		u.z = u.z + dz / dist * self:effectiveSpeed(u) * dt
		self:clampPos(u)
	end

	local target = u.target
	if target and target.alive then
		local td = math.sqrt((target.x - u.x) ^ 2 + (target.z - u.z) ^ 2)
		if td <= u.def.range + target.def.radius and u.attackCd <= 0 and u.def.damage > 0 then
			u.attackCd = u.def.cooldown
			local aura = self:aura(u, "might")
			local dmg = u.def.damage * (1 + (aura and aura.bonus or 0))
			if target.isDevice then
				self:damageDevice(u, target, dmg)
			elseif u.def.ability and u.def.ability.kind == "bounce" then
				self:castAbility(u, target)
			else
				self:fireProjectile(u, target, dmg)
			end
		end
	end
end

function UCSimCore:separate()
	for i = 1, #self.units do
		local a = self.units[i]
		if a.alive then
			for j = i + 1, #self.units do
				local b = self.units[j]
				if b.alive then
					local dx, dz = b.x - a.x, b.z - a.z
					local minDist = a.def.radius + b.def.radius
					local d = math.sqrt(dx * dx + dz * dz)
					if d < minDist and d > 0.01 then
						local push = (minDist - d) * 0.5
						a.x, a.z = a.x - dx / d * push, a.z - dz / d * push
						b.x, b.z = b.x + dx / d * push, b.z + dz / d * push
					end
				end
			end
		end
	end
end

function UCSimCore:stepDevices(dt)
	for i = #self.devices, 1, -1 do
		local d = self.devices[i]
		if self.t >= d.expires or d.hp <= 0 then
			if d.modelEvent then
				self:emit({ type = "despawn", x = d.x, z = d.z })
			end
			table.remove(self.devices, i)
		elseif d.kind == "turret" then
			d.cd = math.max(0, d.cd - dt)
			if d.cd <= 0 then
				local best, bestDist = nil, d.range
				for _, e in ipairs(self.units) do
					if e.alive and e.team ~= d.team then
						local dist = math.sqrt((e.x - d.x) ^ 2 + (e.z - d.z) ^ 2)
						if dist < bestDist then
							best, bestDist = e, dist
						end
					end
				end
				if best then
					d.cd = d.cooldown
					table.insert(self.projectiles, {
						x = d.x, z = d.z, target = best, shooter = nil,
						speed = 60, damage = d.damage,
					})
					self:emit({ type = "shoot", fx = d.x, fz = d.z, tx = best.x, tz = best.z, speed = 60, team = d.team })
				end
			end
		elseif d.kind == "pad" then
			d.tickTimer = d.tickTimer - dt
			if d.tickTimer <= 0 then
				d.tickTimer = 1
				for _, a in ipairs(self.units) do
					if a.alive and a.team == d.team then
						local dist = math.sqrt((a.x - d.x) ^ 2 + (a.z - d.z) ^ 2)
						if dist <= d.radius then
							self:heal(d, a, d.heal)
						end
					end
				end
			end
		end
	end
end

function UCSimCore:step(dt)
	self.t = self.t + dt
	for _, u in ipairs(self.units) do
		self:stepUnit(u, dt)
	end
	self:separate()
	self:stepProjectiles(dt)
	self:stepDevices(dt)
	self.timelineTimer = self.timelineTimer - dt
	if self.timelineTimer <= 0 then
		self.timelineTimer = 1
		table.insert(self.timeline, { a = self:aliveOf("A"), b = self:aliveOf("B") })
	end
	self:checkVictory()
end

function UCSimCore:score(team)
	local s = 0
	for _, u in ipairs(self.units) do
		if u.alive and u.team == team then
			s = s + u.def.cost * (u.hp / u.maxHp)
		end
	end
	return s
end

function UCSimCore:checkVictory()
	if self.outcome then
		return
	end
	local a, b = self:aliveOf("A"), self:aliveOf("B")
	if a == 0 or b == 0 then
		self.outcome = { winner = (a == 0 and b == 0) and "draw" or (a > 0 and "A" or "B"), reason = "annihilation" }
	elseif self.t >= self.timeLimit then
		local sa, sb = self:score("A"), self:score("B")
		local winner = (math.abs(sa - sb) / math.max(1, sa + sb) < 0.02) and "draw" or (sa > sb and "A" or "B")
		self.outcome = { winner = winner, reason = "timeout" }
	end
	if self.outcome then
		self.outcome.duration = self.t
		self:emit({ type = "victory", winner = self.outcome.winner })
	end
end

function UCSimCore:runToEnd(maxTicks)
	local guard = 0
	maxTicks = maxTicks or 30 * 240
	while not self.outcome and guard < maxTicks do
		self:step(TICK)
		guard = guard + 1
	end
	if not self.outcome then
		self.outcome = { winner = "draw", reason = "cap", duration = self.t }
	end
	return self:results()
end

function UCSimCore:results()
	local function teamResult(team)
		local survivors = 0
		for _, u in ipairs(self.units) do
			if u.alive and u.team == team then
				survivors = survivors + 1
			end
		end
		local list = self.config.teams[team]
		return {
			deployed = list and #list or 0,
			survivors = survivors,
			damage = math.floor(self.stats.damage[team]),
			healing = math.floor(self.stats.healing[team]),
			abilities = self.stats.abilities[team],
			deviceDamage = math.floor(self.stats.devices[team]),
		}
	end
	return {
		winner = self.outcome.winner,
		reason = self.outcome.reason,
		duration = math.floor(self.outcome.duration),
		A = teamResult("A"),
		B = teamResult("B"),
	}
end

return UCSimCore
