// ============================================================
// CORE BATTLE SIMULATION — pure, deterministic, headless-capable.
// No DOM, no rendering. Same seed + config => identical battle.
// Fixed timestep: TICK seconds per step().
// ============================================================

import { RNG } from './rng.js';
import { resolveDef, UNITS } from './units.js';
import { FACTIONS } from './factions.js';
import { think, dist, enemiesWithin, alliesWithin, nearestEnemy, FLEE_DURATION, BRAVE_DURATION } from './ai.js';
import { StatsTracker } from './stats.js';

export const TICK = 1 / 30;
export const WORLD = { W: 1600, H: 900 };

// ---------------- spatial grid ----------------
class SpatialGrid {
  constructor(w, h, cell = 80) {
    this.cell = cell; this.cols = Math.ceil(w / cell); this.rows = Math.ceil(h / cell);
    this.buckets = new Array(this.cols * this.rows);
  }
  clear() { for (let i = 0; i < this.buckets.length; i++) this.buckets[i] = undefined; }
  insert(u) {
    const k = this.key(u.x, u.y);
    (this.buckets[k] || (this.buckets[k] = [])).push(u);
  }
  key(x, y) {
    const cx = Math.min(this.cols - 1, Math.max(0, Math.floor(x / this.cell)));
    const cy = Math.min(this.rows - 1, Math.max(0, Math.floor(y / this.cell)));
    return cy * this.cols + cx;
  }
  nearby(x, y, r, out) {
    out.length = 0;
    const c = this.cell;
    const x0 = Math.max(0, Math.floor((x - r) / c)), x1 = Math.min(this.cols - 1, Math.floor((x + r) / c));
    const y0 = Math.max(0, Math.floor((y - r) / c)), y1 = Math.min(this.rows - 1, Math.floor((y + r) / c));
    for (let cy = y0; cy <= y1; cy++) for (let cx = x0; cx <= x1; cx++) {
      const b = this.buckets[cy * this.cols + cx];
      if (b) for (let i = 0; i < b.length; i++) out.push(b[i]);
    }
    return out;
  }
}

// ---------------- unit ----------------
let UID = 1;
export class Unit {
  constructor(def, team, x, y, opts = {}) {
    this.uid = 'u' + (UID++);
    this.def = def;
    this.team = team;
    this.x = x; this.y = y;
    this.vx = 0; this.vy = 0;
    this.hp = def.hp; this.maxHp = def.hp;
    this.shield = 0;
    this.alive = true;
    this.isDecoy = !!opts.isDecoy;
    this.facing = team === 'A' ? 1 : -1;
    this.atkCd = 0;
    this.abilityCd = def.ability ? def.ability.cooldown * 0.35 : 0;
    this.windup = null;
    this.channel = null;
    this.statuses = [];
    this.hitFlash = 0;
    this.deathT = 0;
    this.attackAnim = 0;
    this.walkPhase = 0;
    this.target = null;
    this.moveTarget = null;
    this.thinkTimer = 0;
    this.brainRng = null;
    this.overcharged = false;
    this.dashCrit = false;
    this.momentum = new Map();
  }
  hasUpgrade(id) { return this.def.upgrade === id; }
  hasStatus(type) { return this.statuses.some(s => s.type === type); }
  getStatus(type) { return this.statuses.find(s => s.type === type); }
  speedMul() {
    let m = 1;
    const b = this.getStatus('buff'); if (b) m *= b.power.speed;
    const s = this.getStatus('slow'); if (s) m *= s.power;
    const h = this.getStatus('haste'); if (h) m *= h.power;
    if (this.hasUpgrade('heavy_bulwark2')) m *= 0.85;
    const totem = this.getStatus('totemSpeed'); if (totem) m *= totem.power;
    return m;
  }
  dmgMul() {
    let m = 1;
    const b = this.getStatus('buff'); if (b) m *= b.power.dmg;
    if (this.hasUpgrade('scout_berserk')) m *= 1 + 0.08 * Math.min(3, this.berserkStacks || 0);
    return m;
  }
}

// ---------------- device ids (devices are destructible targets) ----------------
let DEV_SEQ = 1;

// ---------------- projectile ----------------
function makeProjectile(sim, owner, opts) {
  const p = {
    x: opts.x, y: opts.y,
    vx: opts.vx, vy: opts.vy,
    team: owner.team, owner,
    dmg: opts.dmg, type: opts.type, color: opts.color || (owner.def ? owner.def.color : '#fff'),
    life: opts.life || 3, radius: opts.radius || 4,
    bounce: opts.bounce || 0, pierce: opts.pierce || 0,
    gravity: opts.gravity || 0, knockback: opts.knockback || 0,
    crit: opts.crit || 0, homing: opts.homing || null,
    hitSet: new Set(), trail: [], dead: false
  };
  sim.projectiles.push(p);
  if (sim.collectEvents) sim.events.push({ type: 'shot', x: p.x, y: p.y, color: p.color });
  return p;
}

// ---------------- main simulation ----------------
export class BattleSim {
  constructor(config) {
    this.config = config;
    this.seed = config.seed ?? 1;
    this.rng = new RNG(this.seed);
    this.arenaId = config.arena || 'grassland';
    this.modifiers = normalizeModifiers(config.modifiers);
    this.timeLimit = config.timeLimit ?? 90;
    this.collectEvents = config.collectEvents !== false;
    this.W = WORLD.W; this.H = WORLD.H;
    this.t = 0; this.tickCount = 0;
    this.units = [];
    this.projectiles = [];
    this.devices = [];
    this.events = [];
    this.outcome = null;
    this.stats = new StatsTracker(this);
    this.grid = new SpatialGrid(this.W, this.H);
    this._near = [];
    this.shake = 0;

    for (const team of ['A', 'B']) {
      const list = config.teams?.[team]?.units || [];
      for (const s of list) this.spawnUnit(team, s.type, s.x, s.y, s.upgrade, s.hpFrac);
    }
  }

  spawnUnit(team, unitId, x, y, upgrade, hpFrac) {
    const base = resolveDef(unitId, upgrade);
    applyFaction(base, unitId);
    const u = new Unit(base, team, x, y);
    if (hpFrac != null && isFinite(hpFrac)) u.hp = Math.max(1, Math.round(u.maxHp * hpFrac));
    u.brainRng = this.rng;
    u.thinkTimer = this.rng.range(0, 0.15);
    this.units.push(u);
    this.stats.register(u);
    if (this.collectEvents) this.events.push({ type: 'spawn', x, y, team, unitId });
    return u;
  }

  aliveOf(team) {
    let n = 0;
    for (const u of this.units) if (u.alive && u.team === team && !u.isDecoy) n++;
    return n;
  }

  enemiesOf(u) {
    const out = [];
    for (const e of this.units) if (e.alive && e.team !== u.team) out.push(e);
    return out;
  }

  addEvent(ev) {
    if (this.collectEvents) {
      this.events.push(ev);
      if (this.events.length > 3000) this.events.splice(0, 1000);
    }
  }

  // ---------- stepping ----------
  step() {
    if (this.outcome) return;
    const dt = TICK;
    this.t += dt; this.tickCount++;
    this.shake = Math.max(0, this.shake - dt * 3);

    this.grid.clear();
    for (const u of this.units) if (u.alive) this.grid.insert(u);

    for (const u of this.units) {
      if (!u.alive) { u.deathT += dt; continue; }
      this.updateStatuses(u, dt);
      if (!u.alive) continue;
      if (u.hasStatus('stun')) { u.vx *= 0.8; u.vy *= 0.8; continue; }
      this.updateChannel(u, dt);
      this.updateCooldowns(u, dt);
      u.thinkTimer -= dt;
      // Flee/brave cycle: bounded retreat windows so kiting can't stall battles.
      if (u.fleeing) {
        u.fleeTimer = (u.fleeTimer || 0) + dt;
        if (u.fleeTimer >= FLEE_DURATION) { u.fleeing = false; u.braveTimer = BRAVE_DURATION; u.fleeTimer = 0; }
      } else if (u.braveTimer > 0) {
        u.braveTimer -= dt;
      }
      const targetDead = u.attackTarget && !u.attackTarget.alive;
      if (u.thinkTimer <= 0 || targetDead || (!u.moveTarget && !u.attackTarget)) {
        u.thinkTimer = 0.12 + this.rng.next() * 0.08;
        think(this, u);
      }
      this.updateAttack(u, dt);
      this.updateAbility(u, dt);
      this.updateMovement(u, dt);
    }

    this.updateProjectiles(dt);
    this.updateDevices(dt);
    this.updateSeparation(dt);
    this.checkVictory();
  }

  updateStatuses(u, dt) {
    for (let i = u.statuses.length - 1; i >= 0; i--) {
      const s = u.statuses[i];
      s.t -= dt;
      if (s.type === 'regen') this.heal(s.source, u, s.power * dt, { silent: true });
      if (s.type === 'haste' && u.hasUpgrade('scout_berserk')) {
        u.berserkStacks = Math.min(3, (u.berserkStacks || 0) + dt * 2);
      }
      if (s.t <= 0) u.statuses.splice(i, 1);
    }
    u.hitFlash = Math.max(0, u.hitFlash - dt * 4);
    u.attackAnim = Math.max(0, u.attackAnim - dt * 3.5);
  }

  updateCooldowns(u, dt) {
    const rate = u.def.abilityRateMul || 1;
    if (u.abilityCd > 0) u.abilityCd -= dt * rate;
    if (u.atkCd > 0) u.atkCd -= dt;
  }

  updateChannel(u, dt) {
    if (!u.channel) return;
    u.channel.t -= dt;
    if (u.channel.t <= 0) {
      const c = u.channel; u.channel = null;
      if (c.type === 'focus') this.fireFocusedShot(u, c.target);
    }
  }

  // ---------- attacks ----------
  updateAttack(u, dt) {
    if (u.windup) {
      u.windup.t -= dt;
      if (u.windup.t <= 0) {
        const w = u.windup; u.windup = null;
        this.executeAttack(u, w.target);
      }
      return;
    }
    if (u.atkCd > 0 || !u.def.attack) return;
    const t = u.attackTarget;
    if (!t || !t.alive || t.team === u.team) return;
    const range = u.def.attack.range + t.def.radius;
    if (dist(u, t) > range) return;
    u.facing = t.x >= u.x ? 1 : -1;
    u.windup = { t: u.def.attack.windup, target: t };
    u.attackAnim = 1;
  }

  executeAttack(u, target) {
    if (!target || !target.alive || u.atkCd > 0) return;
    const a = u.def.attack;
    u.atkCd = a.cooldown;
    if (a.type === 'melee') {
      this.meleeHit(u, target, a.damage, a.knockback);
    } else {
      this.fireBasicProjectile(u, target);
    }
  }

  meleeHit(u, target, baseDamage, knockback) {
    let dmg = baseDamage * u.dmgMul();
    let crit = false;
    if (u.dashCrit) { dmg *= 1.8; crit = true; u.dashCrit = false; }
    if (u.def.attack.crit && this.rng.chance(u.def.attack.crit)) { dmg *= 1.75; crit = true; }
    if (u.hasUpgrade('sniper_deadeye') && target.hp >= target.maxHp - 0.01) dmg *= 1.5;
    if (u.hasUpgrade('trickster_shadow') && target.facing * (u.x - target.x) < 0) dmg *= 1.6;
    if (u.hasUpgrade('brawler_momentum')) {
      const m = u.momentum.get(target.uid);
      const stacks = m && (this.t - m.t) < 4 ? m.s : 0;
      dmg *= 1 + 0.15 * Math.min(4, stacks);
      u.momentum.set(target.uid, { s: stacks + 1, t: this.t });
    }
    if (u.hasUpgrade('reaper_deathwing') && target.hp < target.maxHp * 0.35) dmg *= 1.6;
    this.damage(u, target, dmg, { crit, knockback, source: 'attack' });
    const ls = u.def.attack.lifesteal;
    if (ls) this.heal(u, u, dmg * ls);
    if (u.hasUpgrade('brawler_quake')) this.addStatus(target, 'slow', 1.5, 0.65);
  }

  fireBasicProjectile(u, target) {
    const a = u.def.attack;
    const kind = a.projectile || 'bolt';
    const speed = kind === 'rail' ? 900 : kind === 'bounce' ? 380 : 460;
    const ang = Math.atan2(target.y - u.y, target.x - u.x) + this.rng.range(-0.03, 0.03);
    const opts = {
      x: u.x + Math.cos(ang) * (u.def.radius + 4), y: u.y + Math.sin(ang) * (u.def.radius + 4),
      vx: Math.cos(ang) * speed, vy: Math.sin(ang) * speed,
      dmg: a.damage * u.dmgMul(), type: kind, knockback: a.knockback || 0,
      crit: a.crit || 0, life: kind === 'rail' ? 1.2 : 2.4
    };
    if (kind === 'bounce') {
      opts.bounce = (u.overcharged ? 5 : (a.bounce || 2)) + (u.hasUpgrade('caster_storm') ? 2 : 0);
      if (u.overcharged) opts.dmg *= 1.5;
      u.overcharged = false;
    }
    if (kind === 'seed') opts.gravity = this.mod('lowGravity') ? 260 : 520;
    makeProjectile(this, u, opts);
  }

  fireFocusedShot(u, target) {
    if (!target || !target.alive) return;
    const pierce = u.hasUpgrade('sniper_pierceup') ? 99 : 1;
    const ang = Math.atan2(target.y - u.y, target.x - u.x);
    makeProjectile(this, u, {
      x: u.x, y: u.y, vx: Math.cos(ang) * 1100, vy: Math.sin(ang) * 1100,
      dmg: 110 * u.dmgMul(), type: 'rail', pierce, knockback: 120, life: 1.0, radius: 6,
      color: '#fff2a8'
    });
    this.addEvent({ type: 'ability', x: u.x, y: u.y, name: 'Focused Shot', color: '#fff2a8' });
    this.stats.addAbility(u);
    this.shake += 0.3;
  }

  // ---------- abilities ----------
  updateAbility(u, dt) {
    if (!u.def.ability || u.abilityCd > 0 || !u.abilityRequested) return;
    this.castAbility(u);
  }

  setHealTarget(u, t) { u.healTarget = t; }

  castAbility(u) {
    const ab = u.def.ability;
    u.abilityCd = ab.cooldown;
    this.stats.addAbility(u);
    this.addEvent({ type: 'ability', x: u.x, y: u.y, name: ab.name, color: u.def.color, team: u.team });
    switch (u.def.id) {
      case 'scout': return this.abDash(u);
      case 'guardian': return this.abBulwark(u);
      case 'brawler': return this.abCleave(u);
      case 'medic': return this.abHealBeam(u);
      case 'heavy': return this.abSlam(u);
      case 'sparkcaster': return this.abOvercharge(u);
      case 'sniper': return this.abFocus(u);
      case 'engineer': return this.abTurret(u);
      case 'disruptor': return this.abLeash(u);
      case 'commander': return this.abCry(u);
      case 'trickster': return this.abBlink(u);
      case 'artificer': return this.abTotem(u);
      case 'colossus': return this.abSweep(u);
      case 'phoenix': return this.abImmolate(u);
      case 'reaper': return this.abSiphon(u);
    }
  }

  abDash(u) {
    const t = u.attackTarget || nearestEnemy(this, u);
    if (!t) return;
    const ang = Math.atan2(t.y - u.y, t.x - u.x);
    u.vx = Math.cos(ang) * 620; u.vy = Math.sin(ang) * 620;
    u.dashCrit = true;
    this.addStatus(u, 'haste', 0.8, 1.6);
    if (u.hasUpgrade('scout_phantom')) this.spawnDecoy(u, u.x, u.y, 2.5, 40);
  }

  abBulwark(u) {
    const r = u.hasUpgrade('guardian_bulwark') ? 165 : 110;
    const amt = u.hasUpgrade('guardian_bulwark') ? 63 : 45;
    for (const a of alliesWithin(this, u, r, true)) {
      a.shield = Math.min(a.maxHp * 0.6, a.shield + amt);
      this.addStatus(a, 'shield', 4, 1);
      this.addEvent({ type: 'shield', x: a.x, y: a.y, color: '#8fd3ff' });
    }
  }

  // ---------- devices are destructible: no more uncounterable Engineer ----------
  damageDevice(attacker, device, amount) {
    if (!device || device.hp <= 0 || amount <= 0) return;
    device.hp -= amount;
    if (device.hp <= 0) device.hp = 0;
    if (this.collectEvents) this.events.push({ type: 'deviceHit', x: device.x, y: device.y, color: device.def.color });
  }

  damageDevices(attacker, x, y, r, dmg) {
    for (const d of this.devices) {
      if (d.team === attacker.team || d.hp <= 0) continue;
      if (Math.hypot(d.x - x, d.y - y) > r + (d.def.radius || 10)) continue;
      this.damageDevice(attacker, d, dmg);
    }
  }

  abCleave(u) {
    const r = u.def.attack.range + 18;
    for (const t of enemiesWithin(this, u, r)) {
      this.damage(u, t, u.def.attack.damage * 1.5 * u.dmgMul(), { knockback: 110 });
      if (u.hasUpgrade('brawler_quake')) this.addStatus(t, 'slow', 1.5, 0.65);
    }
    this.damageDevices(u, u.x, u.y, r, u.def.attack.damage);
    this.addEvent({ type: 'aoe', x: u.x, y: u.y, r, color: '#ffd97a' });
    this.shake += 0.25;
  }

  abHealBeam(u) {
    const t = u.healTarget;
    if (!t || !t.alive || !t.team || t.team !== u.team || dist(u, t) > 190) { u.abilityCd = 1; return; }
    this.heal(u, t, 26 * (u.def.healingMul || 1));
    if (u.hasUpgrade('medic_triage')) {
      t.statuses = t.statuses.filter(s => s.type !== 'stun' && s.type !== 'slow');
    }
    if (u.hasUpgrade('medic_bloom')) this.addStatus(t, 'regen', 2, 6, u);
    this.addEvent({ type: 'heal', x: t.x, y: t.y, color: '#8fce6f', from: { x: u.x, y: u.y } });
  }

  abSlam(u) {
    const r = u.hasUpgrade('heavy_seismic') ? 152 : 95;
    for (const t of enemiesWithin(this, u, r)) {
      this.damage(u, t, 34 * u.dmgMul(), { knockback: 320 });
      if (u.hasUpgrade('heavy_seismic')) this.addStatus(t, 'stun', 0.5, 1);
    }
    this.damageDevices(u, u.x, u.y, r, 30);
    this.addEvent({ type: 'aoe', x: u.x, y: u.y, r, color: '#ff9c5f' });
    this.shake += 0.8;
  }

  abOvercharge(u) {
    u.overcharged = true;
    if (u.hasUpgrade('caster_overload')) {
      for (let i = 0; i < 6; i++) {
        const ang = (i / 6) * Math.PI * 2;
        makeProjectile(this, u, {
          x: u.x, y: u.y, vx: Math.cos(ang) * 300, vy: Math.sin(ang) * 300,
          dmg: 8, type: 'bolt', knockback: 10, life: 1.4, color: '#e0b0ff'
        });
      }
    }
  }

  abFocus(u) {
    const t = u.attackTarget || nearestEnemy(this, u);
    if (t) u.channel = { t: 1.2, type: 'focus', target: t };
    else u.abilityCd = 1;
  }

  abTurret(u) {
    const life = 20 * (u.def.deviceLifeMul || 1);
    const rate = 0.8 / (u.def.deviceRateMul || 1);
    this.devices.push({
      kind: 'turret', uid: 'd' + (DEV_SEQ++), team: u.team, owner: u, x: u.x - u.facing * 20, y: u.y,
      hp: 70, maxHp: 70, life, cd: 0.5, rate, dmg: 12,
      boosted: u.hasUpgrade('engineer_upgradeturret'),
      def: { id: 'turret', name: 'Turret', category: 'device', radius: 10, color: '#f0a35e' }
    });
  }

  abLeash(u) {
    const t = u.attackTarget || nearestEnemy(this, u);
    if (!t) { u.abilityCd = 1; return; }
    makeProjectile(this, u, {
      x: u.x, y: u.y, vx: 0, vy: 0, dmg: 10, type: 'leash', homing: t,
      life: 2.2, radius: 6, color: '#e57bd0', knockback: 0
    });
  }

  abCry(u) {
    const dmgB = u.hasUpgrade('commander_warlord') ? 1.25 : 1.15;
    const spd = u.hasUpgrade('commander_warlord') ? 1.15 : 1.2;
    for (const a of alliesWithin(this, u, 200, true)) {
      this.addStatus(a, 'buff', 5, { dmg: dmgB, speed: spd });
      if (u.hasUpgrade('commander_phoenix')) this.heal(u, a, 25);
      this.addEvent({ type: 'buff', x: a.x, y: a.y, color: '#f2e27a' });
    }
  }

  abBlink(u) {
    const back = nearestEnemy(this, u, e => ['ranged', 'support', 'commander'].includes(e.def.category));
    const t = back || nearestEnemy(this, u);
    if (!t) return;
    const ang = this.rng.angle();
    u.x = clamp(t.x + Math.cos(ang) * 30, 20, this.W - 20);
    u.y = clamp(t.y + Math.sin(ang) * 30, 20, this.H - 20);
    u.vx = 0; u.vy = 0;
    this.spawnDecoy(u, u.x, u.y, 6, 60);
    this.addEvent({ type: 'blink', x: u.x, y: u.y, color: u.def.color });
  }

  abTotem(u) {
    const life = 12 * (u.def.deviceLifeMul || 1);
    this.devices.push({
      kind: 'totem', uid: 'd' + (DEV_SEQ++), team: u.team, owner: u,
      x: clamp(u.x, 40, this.W - 40), y: clamp(u.y, 40, this.H - 40),
      hp: 60, maxHp: 60, life, healRate: 9 * (u.def.healingMul || 1),
      radius: 110, speedAura: u.hasUpgrade('artificer_grove'),
      def: { id: 'totem', name: 'Totem', category: 'device', radius: 12, color: '#a5e07a' }
    });
  }

  abSweep(u) {
    for (const t of enemiesWithin(this, u, 130)) {
      this.damage(u, t, 55 * u.dmgMul(), { knockback: 420 });
    }
    this.damageDevices(u, u.x, u.y, 130, 55);
    if (u.hasUpgrade('colossus_meteor')) {
      const es = this.enemiesOf(u).filter(e => e.alive).slice(0, 5);
      for (const e of es) {
        makeProjectile(this, u, {
          x: e.x + this.rng.range(-60, 60), y: e.y - 300,
          vx: this.rng.range(-20, 20), vy: 480,
          dmg: 24, type: 'debris', gravity: 300, knockback: 100, life: 2, radius: 7, color: '#ff9c5f'
        });
      }
    }
    this.addEvent({ type: 'aoe', x: u.x, y: u.y, r: 130, color: '#ffd97a' });
    this.shake += 1;
  }

  abImmolate(u) {
    for (const e of enemiesWithin(this, u, 130)) {
      this.damage(u, e, 22 * u.dmgMul(), { knockback: 90 });
    }
    this.damageDevices(u, u.x, u.y, 130, 22);
    this.addStatus(u, 'haste', 2.5, 1.4);
    this.addEvent({ type: 'aoe', x: u.x, y: u.y, r: 130, color: '#ff9d5c' });
    this.shake += 0.4;
  }

  abSiphon(u) {
    let best = null, score = -Infinity;
    for (const e of enemiesWithin(this, u, 200)) {
      const missing = (e.maxHp - e.hp) / e.maxHp;
      const s = missing * 100 - dist(u, e) * 0.05;
      if (s > score) { score = s; best = e; }
    }
    if (!best) return;
    const dealt = this.damage(u, best, 40 * u.dmgMul(), { knockback: 60 });
    this.heal(u, u, dealt * 0.8);
    this.addEvent({ type: 'heal', x: u.x, y: u.y - 10, amount: Math.round(dealt * 0.8), color: '#9de07a' });
  }

  spawnDecoy(owner, x, y, life, hp) {
    const u = new Unit(decoyDef(), owner.team, x, y, { isDecoy: true });
    u.hp = hp; u.maxHp = hp;
    u.brainRng = this.rng;
    u.decoyLife = life;
    u.decoyOwner = owner;
    this.units.push(u);
    return u;
  }

  // ---------- damage & healing ----------
  damage(attacker, target, amount, opts = {}) {
    if (!target.alive || amount <= 0) return 0;
    let amt = amount;
    let armor = target.def.armor || 0;
    if (target.def.formationArmor && alliesWithin(this, target, 120, true).length >= 2) armor += target.def.formationArmor;
    if (target.hasUpgrade('colossus_titan') && target.hp < target.maxHp * 0.4) armor += 0.3;
    if (target.hasStatus('silence') && target.hasStatus('feedback')) amt *= 1.15;
    amt *= Math.max(0.15, 1 - armor);
    if (target.shield > 0) {
      const absorbed = Math.min(target.shield, amt);
      target.shield -= absorbed; amt -= absorbed;
      if (absorbed > 0) this.addEvent({ type: 'absorb', x: target.x, y: target.y, color: '#8fd3ff' });
    }
    if (target.hasUpgrade('guardian_react') && opts.source === 'attack' && attacker && attacker.alive) {
      this.damage(target, attacker, amount * 0.2, { source: 'reflect' });
    }
    if (amt <= 0) { this.stats.addDamage(attacker, target, 0); return 0; }
    target.hp -= amt;
    target.hitFlash = 1;
    this.stats.addDamage(attacker, target, amt);
    if (opts.knockback) this.knockback(target, opts.knockback, attacker);
    this.addEvent({
      type: 'hit', x: target.x, y: target.y - target.def.radius - 4,
      dmg: Math.round(amt), crit: !!opts.crit, team: target.team
    });
    if (target.hp <= 0) this.kill(attacker, target);
    return amt;
  }

  knockback(target, force, from) {
    let mul = 1;
    if (this.mod('lowGravity')) mul *= 1.4;
    if (this.mod('heavyKnockback')) mul *= 1.8;
    let ang;
    if (from && from !== target) ang = Math.atan2(target.y - from.y, target.x - from.x);
    else ang = this.rng.angle();
    target.vx += Math.cos(ang) * force * mul;
    target.vy += Math.sin(ang) * force * mul;
  }

  heal(source, target, amount, opts = {}) {
    if (!target.alive || amount <= 0) return;
    const amt = Math.min(amount, target.maxHp - target.hp);
    if (amt <= 0) return;
    target.hp += amt;
    if (source && source.def && source.def.id !== 'decoy') this.stats.addHeal(source, target, amt);
    if (!opts.silent) this.addEvent({ type: 'heal', x: target.x, y: target.y - 10, amount: Math.round(amt), color: '#8fce6f' });
  }

  kill(killer, target) {
    if (!target.alive) return;
    if (this.rebirth(target)) return;
    target.alive = false;
    target.hp = 0;
    target.deathT = 0;
    if (target.isDecoy) {
      if (target.decoyOwner && target.decoyOwner.hasUpgrade('trickster_mirage')) {
        for (const e of enemiesWithin(this, target, 70)) {
          this.damage(target.decoyOwner, e, 26, { knockback: 80 });
        }
        this.addEvent({ type: 'aoe', x: target.x, y: target.y, r: 70, color: '#e57bd0' });
      }
      this.addEvent({ type: 'decoyPop', x: target.x, y: target.y });
      return;
    }
    this.stats.addKill(killer && !killer.isDecoy ? killer : null, target);
    this.addEvent({ type: 'death', x: target.x, y: target.y, team: target.team, unitId: target.def.id, big: target.def.cost >= 300 });
    if (target.def.cost >= 300) { this.addEvent({ type: 'shake', power: 1.2 }); this.shake += 1.2; }
  }

  // Phoenix-style one-time rebirth: deny death, detonate a nova, rise again.
  rebirth(target) {
    const rb = target.def.rebirth;
    if (!rb || target.rebirthUsed) return false;
    target.rebirthUsed = true;
    const bigger = target.hasUpgrade('phoenix_ember');
    const radius = rb.novaRadius * (bigger ? 1.4 : 1);
    const hpFrac = rb.hpFrac + (target.hasUpgrade('phoenix_solar') ? 0.15 : 0);
    target.hp = target.maxHp * hpFrac;
    target.statuses = [];
    for (const e of enemiesWithin(this, target, radius)) {
      this.damage(target, e, rb.novaDamage, { knockback: rb.novaKnockback });
      if (bigger) this.addStatus(e, 'slow', 2, 0.6, target);
    }
    this.damageDevices(target, target.x, target.y, radius, rb.novaDamage);
    this.addEvent({ type: 'rebirth', x: target.x, y: target.y, r: radius, color: '#ff9d5c' });
    this.shake += 0.8;
    return true;
  }

  addStatus(target, type, dur, power, source) {
    const existing = target.getStatus(type);
    if (existing && type !== 'stun') { existing.t = Math.max(existing.t, dur); existing.power = power; existing.source = source || existing.source; return; }
    target.statuses.push({ type, t: dur, power, source });
  }

  // ---------- projectiles ----------
  updateProjectiles(dt) {
    const wind = this.mod('wind') ? 60 : 0;
    for (let i = this.projectiles.length - 1; i >= 0; i--) {
      const p = this.projectiles[i];
      p.life -= dt;
      if (p.life <= 0) { this.projectiles.splice(i, 1); continue; }
      if (p.type === 'leash') {
        const t = p.homing;
        if (!t || !t.alive) { this.projectiles.splice(i, 1); continue; }
        const ang = Math.atan2(t.y - p.y, t.x - p.x);
        const sp = Math.min(560, Math.hypot(p.vx || 0, p.vy || 0) + 900 * dt);
        p.vx = Math.cos(ang) * sp; p.vy = Math.sin(ang) * sp;
      }
      p.vy += (p.gravity || 0) * dt;
      p.vx += wind * dt;
      p.x += p.vx * dt; p.y += p.vy * dt;
      p.trail.push(p.x, p.y);
      if (p.trail.length > 14) p.trail.splice(0, 2);

      if (p.x < -50 || p.x > this.W + 50 || p.y < -80 || p.y > this.H + 50) {
        this.projectiles.splice(i, 1); continue;
      }
      this.grid.nearby(p.x, p.y, 30, this._near);
      let consumed = false;
      for (const u of this._near) {
        if (!u.alive || u.team === p.team || p.hitSet.has(u.uid)) continue;
        if (dist(p, u) > u.def.radius + p.radius) continue;
        p.hitSet.add(u.uid);
        let dmg = p.dmg, crit = false;
        if (p.crit && this.rng.chance(p.crit)) { dmg *= 1.75; crit = true; }
        this.damage(p.owner, u, dmg, { crit, knockback: p.knockback });
        if (p.type === 'leash') {
          this.addStatus(u, 'stun', 1.2, 1);
          this.addStatus(u, 'slow', 2.5, 0.6);
          if (p.owner.hasUpgrade && p.owner.hasUpgrade('disruptor_blackout')) {
            this.addStatus(u, 'silence', 3, 1);
            this.addStatus(u, 'feedback', 3, 1);
            u.shield = 0;
          } else {
            this.addStatus(u, 'silence', 1.5, 1);
          }
          this.addEvent({ type: 'aoe', x: u.x, y: u.y, r: 30, color: '#e57bd0' });
          consumed = true;
        } else if (p.type === 'bounce' && p.bounce > 0) {
          p.bounce--;
          p.dmg *= 0.8;
          const next = this.nearestOtherEnemy(u, p);
          if (next) {
            const ang = Math.atan2(next.y - p.y, next.x - p.x);
            const sp = Math.hypot(p.vx, p.vy);
            p.vx = Math.cos(ang) * sp; p.vy = Math.sin(ang) * sp;
            this.addEvent({ type: 'bounce', x: p.x, y: p.y, color: p.color });
          } else consumed = true;
        } else if (p.pierce > 0) {
          p.pierce--;
        } else {
          consumed = true;
        }
        if (consumed) break;
      }
      if (!consumed && p.type !== 'leash') {
        for (const d of this.devices) {
          if (d.team === p.team || d.hp <= 0 || p.hitSet.has(d.uid)) continue;
          if (Math.hypot(d.x - p.x, d.y - p.y) > (d.def.radius || 10) + p.radius) continue;
          p.hitSet.add(d.uid);
          this.damageDevice(p.owner, d, p.dmg);
          consumed = true;
          break;
        }
      }
      if (consumed) this.projectiles.splice(i, 1);
    }
  }

  nearestOtherEnemy(from, p) {
    let best = null, bd = 150;
    for (const e of this.units) {
      if (!e.alive || e.team === p.team || p.hitSet.has(e.uid)) continue;
      const d = dist(p, e);
      if (d < bd) { bd = d; best = e; }
    }
    return best;
  }

  // ---------- devices ----------
  updateDevices(dt) {
    for (let i = this.devices.length - 1; i >= 0; i--) {
      const d = this.devices[i];
      d.life -= dt;
      if (d.hp <= 0 || d.life <= 0) {
        this.devices.splice(i, 1);
        this.addEvent({ type: 'deviceDown', x: d.x, y: d.y, kind: d.kind, color: d.def.color });
        continue;
      }
      if (d.kind === 'turret') {
        d.cd -= dt;
        if (d.cd <= 0) {
          const t = this.nearestEnemyToPoint(d.x, d.y, d.team, 230);
          if (t) {
            d.cd = d.rate * (d.boosted ? 0.6 : 1);
            const ang = Math.atan2(t.y - d.y, t.x - d.x);
            makeProjectile(this, d.owner || { team: d.team, def: { color: '#f0a35e', radius: 8 } }, {
              x: d.x, y: d.y, vx: Math.cos(ang) * 500, vy: Math.sin(ang) * 500,
              dmg: d.dmg, type: d.boosted ? 'bounce' : 'bolt', bounce: d.boosted ? 1 : 0,
              knockback: 15, life: 1.4, color: '#f0a35e'
            });
          } else d.cd = 0.2;
        }
      } else if (d.kind === 'totem') {
        for (const a of this.units) {
          if (!a.alive || a.team !== d.team || a.isDecoy) continue;
          if (dist(a, d) <= d.radius) {
            this.heal(d.owner, a, d.healRate * dt, { silent: true });
            if (d.speedAura) this.addStatus(a, 'totemSpeed', 0.3, 1.15, d.owner);
            if (this.collectEvents && this.rng.chance(0.05)) this.events.push({ type: 'heal', x: a.x, y: a.y, color: '#a5e07a' });
          }
        }
      }
    }
  }

  nearestEnemyToPoint(x, y, team, r) {
    let best = null, bd = r;
    for (const u of this.units) {
      if (!u.alive || u.team === team || u.isDecoy) continue;
      const d = Math.hypot(u.x - x, u.y - y);
      if (d < bd) { bd = d; best = u; }
    }
    return best;
  }

  // ---------- movement ----------
  updateMovement(u, dt) {
    if (u.isDecoy) {
      u.vx *= Math.exp(-6 * dt); u.vy *= Math.exp(-6 * dt);
      this.integrate(u, dt);
      return;
    }
    const slippery = this.mod('slippery');
    const speed = (u.def.speed || 60) * u.speedMul() * (u.windup || u.channel ? 0.25 : 1) * (u.fleeing ? 0.85 : 1);
    if (u.moveTarget) {
      const dx = u.moveTarget.x - u.x, dy = u.moveTarget.y - u.y;
      const d = Math.hypot(dx, dy);
      if (d > 6) {
        const wantVx = (dx / d) * speed, wantVy = (dy / d) * speed;
        const k = Math.min(1, (slippery ? 3.2 : 9) * dt);
        u.vx += (wantVx - u.vx) * k;
        u.vy += (wantVy - u.vy) * k;
      }
    }
    const fr = Math.exp(-(slippery ? 1.6 : 7) * dt);
    if (!u.moveTarget || Math.hypot(u.vx, u.vy) > speed * 1.6) {
      u.vx *= fr; u.vy *= fr;
    }
    this.integrate(u, dt);
  }

  integrate(u, dt) {
    u.x += u.vx * dt; u.y += u.vy * dt;
    const r = u.def.radius || 9;
    if (u.x < r) { u.x = r; u.vx = Math.abs(u.vx) * 0.4; }
    if (u.x > this.W - r) { u.x = this.W - r; u.vx = -Math.abs(u.vx) * 0.4; }
    if (u.y < r) { u.y = r; u.vy = Math.abs(u.vy) * 0.4; }
    if (u.y > this.H - r) { u.y = this.H - r; u.vy = -Math.abs(u.vy) * 0.4; }
    if (Math.abs(u.vx) > 8) u.facing = u.vx > 0 ? 1 : -1;
    if (Math.hypot(u.vx, u.vy) > 12) u.walkPhase += dt * 9;
  }

  updateSeparation(dt) {
    const near = [];
    for (const u of this.units) {
      if (!u.alive) continue;
      this.grid.nearby(u.x, u.y, 40, near);
      for (const o of near) {
        if (o === u || !o.alive) continue;
        const dx = u.x - o.x, dy = u.y - o.y;
        const rr = (u.def.radius + o.def.radius) * 0.9;
        const d2 = dx * dx + dy * dy;
        if (d2 < rr * rr && d2 > 0.0001) {
          const d = Math.sqrt(d2);
          const push = (rr - d) / d * (o.team === u.team ? 0.5 : 0.35);
          u.x += dx * push * 0.5; u.y += dy * push * 0.5;
        }
      }
    }
  }

  // ---------- victory ----------
  checkVictory() {
    const a = this.aliveOf('A'), b = this.aliveOf('B');
    if (a === 0 || b === 0) {
      if (a === 0 && b === 0) this.outcome = { winner: 'draw', reason: 'mutual', duration: this.t };
      else this.outcome = { winner: a > 0 ? 'A' : 'B', reason: 'annihilation', duration: this.t };
      this.addEvent({ type: 'victory', winner: this.outcome.winner });
      return;
    }
    if (this.t >= this.timeLimit) {
      const score = (team) => {
        let s = 0;
        for (const u of this.units) if (u.alive && u.team === team && !u.isDecoy) s += u.def.cost * (u.hp / u.maxHp);
        return s;
      };
      const sa = score('A'), sb = score('B');
      const diff = Math.abs(sa - sb) / Math.max(1, sa + sb);
      this.outcome = diff < 0.02 ? { winner: 'draw', reason: 'timeout', duration: this.t }
        : { winner: sa > sb ? 'A' : 'B', reason: 'timeout', duration: this.t };
      this.addEvent({ type: 'victory', winner: this.outcome.winner });
    }
  }

  mod(m) { return !!this.modifiers[m]; }

  drainEvents() {
    const e = this.events;
    this.events = [];
    return e;
  }

  // Headless helper: run to completion with a hard tick cap.
  runToEnd(maxTicks = 30 * 240) {
    let guard = 0;
    while (!this.outcome && guard < maxTicks) { this.step(); guard++; }
    if (!this.outcome) this.outcome = { winner: 'draw', reason: 'cap', duration: this.t };
    return this.stats.snapshot();
  }
}

function normalizeModifiers(mods) {
  if (!mods) return {};
  if (Array.isArray(mods)) { const o = {}; for (const m of mods) o[m] = true; return o; }
  return { ...mods };
}

function applyFaction(def, unitId) {
  const base = UNITS[unitId];
  const fac = FACTIONS[base.faction];
  if (fac) fac.apply(def);
  return def;
}

let _decoyDef = null;
function decoyDef() {
  if (!_decoyDef) {
    _decoyDef = {
      id: 'decoy', name: 'Decoy', category: 'decoy', faction: null,
      cost: 0, hp: 50, speed: 0, radius: 9, armor: 0,
      attack: { range: 0, damage: 0, cooldown: 99, type: 'melee', windup: 0.5 },
      visual: { shape: 'decoy', size: 0.85 },
      color: '#e57bd0', accent: '#7a2f6a'
    };
  }
  return JSON.parse(JSON.stringify(_decoyDef));
}

function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
