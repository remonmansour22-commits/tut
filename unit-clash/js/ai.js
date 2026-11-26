// Reusable behaviour modules. Brains are small state machines driven by
// perception helpers — no unit has its own bespoke AI system.
// A brain must set on `u` (the unit): u.moveTarget, u.attackTarget,
// u.abilityRequested, and may set u.fleeing.

export const BACKLINE = new Set(['ranged', 'support', 'commander', 'specialist']);

export function nearestEnemy(sim, u, filter) {
  let best = null, bd = Infinity;
  for (const e of sim.units) {
    if (!e.alive || e.team === u.team) continue;
    if (filter && !filter(e)) continue;
    const d = dist(u, e);
    if (d < bd) { bd = d; best = e; }
  }
  return best;
}

export function enemiesWithin(sim, u, r) {
  const out = [];
  for (const e of sim.units) {
    if (!e.alive || e.team === u.team) continue;
    if (dist(u, e) <= r) out.push(e);
  }
  return out;
}

export function alliesWithin(sim, u, r, includeSelf = false) {
  const out = [];
  for (const a of sim.units) {
    if (!a.alive || a.team !== u.team) continue;
    if (!includeSelf && a === u) continue;
    if (dist(u, a) <= r) out.push(a);
  }
  return out;
}

export function mostWoundedAlly(sim, u, r) {
  let best = null, score = -Infinity;
  for (const a of sim.units) {
    if (!a.alive || a.team !== u.team || a === u) continue;
    if (a.hp >= a.maxHp) continue;
    const d = dist(u, a);
    if (d > r) continue;
    const missing = (a.maxHp - a.hp) / a.maxHp;
    const s = missing * 100 - d * 0.02 + (a.def.category === 'frontline' || a.def.category === 'heavy' ? 15 : 0);
    if (s > score) { score = s; best = a; }
  }
  return best;
}

// Closest living enemy device (turret/totem) within r, or null.
export function nearestEnemyDevice(sim, u, r) {
  let best = null, bd = r;
  for (const d of sim.devices) {
    if (d.team === u.team || !d.alive || d.hp <= 0) continue;
    const dd = dist(u, d);
    if (dd < bd) { bd = dd; best = d; }
  }
  return best;
}

// Counterplay: turrets are priorities. Units in range shoot them without
// repositioning; melee units will walk to one even past a nearby enemy.
// Healing pads only draw fire when no unit target exists.
export function devicePriority(sim, u) {
  if (!u.def.attack || u.def.attack.damage <= 0) return;
  const dev = nearestEnemyDevice(sim, u, u.def.attack.range + 30);
  if (!dev) return;
  const reach = u.def.attack.range + (dev.def.radius || 10);
  const inRange = dist(u, dev) <= reach;
  const melee = u.def.attack.type === 'melee';
  if (dev.kind === 'turret' && (inRange || melee)) {
    u.attackTarget = dev;
    if (!inRange) u.moveTarget = { x: dev.x, y: dev.y };
  } else if (dev.kind !== 'turret' && !u.attackTarget && inRange) {
    u.attackTarget = dev;
  }
}

export function enemyCentroid(sim, u) {
  let x = 0, y = 0, n = 0;
  for (const e of sim.units) {
    if (!e.alive || e.team === u.team) continue;
    x += e.x; y += e.y; n++;
  }
  return n ? { x: x / n, y: y / n } : { x: sim.W * (u.team === 'A' ? 0.8 : 0.2), y: sim.H / 2 };
}

export function allyFrontlineCentroid(sim, u) {
  let x = 0, y = 0, n = 0;
  for (const a of sim.units) {
    if (!a.alive || a.team !== u.team || a === u) continue;
    if (a.def.category === 'frontline' || a.def.category === 'heavy') { x += a.x; y += a.y; n++; }
  }
  if (n) return { x: x / n, y: y / n };
  return allyCentroid(sim, u);
}

export function allyCentroid(sim, u) {
  let x = 0, y = 0, n = 0;
  for (const a of sim.units) {
    if (!a.alive || a.team !== u.team || a === u) continue;
    x += a.x; y += a.y; n++;
  }
  return n ? { x: x / n, y: y / n } : { x: u.x, y: u.y };
}

// Point at distance d from p, away from the enemy side (retreat / behind lines)
export function behindOf(sim, u, p, d) {
  const ec = enemyCentroid(sim, u);
  const dx = p.x - ec.x, dy = p.y - ec.y;
  const len = Math.hypot(dx, dy) || 1;
  return { x: p.x + (dx / len) * d, y: p.y + (dy / len) * d };
}

export function dist(a, b) { return Math.hypot(a.x - b.x, a.y - b.y); }

// Shared self-preservation: fragile units pull back when badly hurt — but only
// for a bounded window, then they find their courage and re-engage. Without the
// bravery cycle, fast ranged units could kite slow melee forever.
export const FLEE_DURATION = 3;
export const BRAVE_DURATION = 4;
function retreatIfHurt(sim, u, threshold = 0.28) {
  if (u.braveTimer > 0) return false;
  if (u.hp >= u.maxHp * threshold) return false;
  const danger = enemiesWithin(sim, u, 210);
  if (!danger.length) return false;
  danger.sort((a, b) => dist(u, a) - dist(u, b));
  u.moveTarget = behindOf(sim, u, u, 150);
  u.fleeing = true;
  return true;
}

function hold(u, p, jitter = 6) {
  u.moveTarget = { x: p.x + u.brainRng.range(-jitter, jitter), y: p.y + u.brainRng.range(-jitter, jitter) };
}

function pursue(u, t, pad = 0) {
  const d = dist(u, t) || 1;
  const stop = (u.def.attack.range * 0.85) + t.def.radius + pad;
  const f = Math.max(0, d - stop);
  u.moveTarget = { x: u.x + ((t.x - u.x) / d) * f, y: u.y + ((t.y - u.y) / d) * f };
}

function kite(u, t, minRange) {
  const d = dist(u, t) || 1;
  if (d < minRange) {
    u.moveTarget = { x: u.x + ((u.x - t.x) / d) * 60, y: u.y + ((u.y - t.y) / d) * 60 };
  }
}

function strafe(u, t) {
  const d = dist(u, t) || 1;
  const px = -(t.y - u.y) / d, py = (t.x - u.x) / d;
  const dir = u.strafeDir || (u.strafeDir = (u.brainRng.chance(0.5) ? 1 : -1));
  u.moveTarget = { x: u.x + px * dir * 40, y: u.y + py * dir * 40 };
  if (u.brainRng.chance(0.015)) u.strafeDir *= -1;
}

// ---------- BRAINS ----------

export const BRAINS = {
  brawler: (sim, u) => {
    const t = nearestEnemy(sim, u) || null;
    u.attackTarget = t;
    if (t) {
      pursue(u, t);
      const crowd = enemiesWithin(sim, u, u.def.attack.range + 14);
      if (crowd.length >= 2 && u.abilityCd <= 0) u.abilityRequested = true;
    } else hold(u, { x: sim.W / 2, y: sim.H / 2 }, 60);
  },

  skirmisher: (sim, u) => {
    // Prefer backline prey within sensing range; otherwise nearest.
    const prey = nearestEnemy(sim, u, e => BACKLINE.has(e.def.category) && dist(u, e) < 420);
    const t = prey || nearestEnemy(sim, u);
    u.attackTarget = t;
    if (u.hp < u.maxHp * 0.28) {
      // Full disengage: stop attacking while fleeing so lifesteal/regen can
      // actually restore the unit instead of dying to chip damage mid-retreat.
      u.fleeing = true;
      u.attackTarget = null;
      hold(u, behindOf(sim, u, u, 160), 20);
      return;
    }
    u.fleeing = false;
    if (t) {
      const d = dist(u, t);
      if (u.abilityCd <= 0 && d > 120 && d < 320 && t.def.category !== 'heavy') u.abilityRequested = true;
      if (d < 90) strafe(u, t); else pursue(u, t, 6);
    } else hold(u, { x: sim.W / 2, y: u.y }, 50);
  },

  trickster: (sim, u) => {
    const back = nearestEnemy(sim, u, e => BACKLINE.has(e.def.category));
    const t = back || nearestEnemy(sim, u);
    u.attackTarget = t;
    if (u.hp < u.maxHp * 0.45 && u.abilityCd <= 0) u.abilityRequested = true;
    else if (u.abilityCd <= 0 && t && BACKLINE.has(t.def.category) && dist(u, t) > 90) u.abilityRequested = true;
    if (t) {
      if (dist(u, t) < 80) strafe(u, t); else pursue(u, t, 4);
    } else hold(u, { x: sim.W / 2, y: u.y }, 50);
  },

  guardian: (sim, u) => {
    // Position between the biggest enemy threat and our fragile allies.
    const fragile = sim.units.filter(a => a.alive && a.team === u.team && a !== u && BACKLINE.has(a.def.category));
    const anchor = fragile.length ? allyFrontlineCentroid(sim, u) : allyCentroid(sim, u);
    // Real threat selection: the enemy that endangers the most fragile allies.
    let threat = null, threatScore = -Infinity;
    for (const e of sim.units) {
      if (!e.alive || e.team === u.team) continue;
      let s = 0;
      for (const f of fragile) {
        const d = dist(e, f);
        if (d < 260) s += (260 - d) / 260 * (f.hp < f.maxHp * 0.5 ? 1.5 : 1);
      }
      s -= dist(e, u) * 0.002;
      if (s > threatScore) { threatScore = s; threat = e; }
    }
    let px, py;
    if (fragile.length && threat) {
      const dx = threat.x - anchor.x, dy = threat.y - anchor.y;
      const l = Math.hypot(dx, dy) || 1;
      px = anchor.x + (dx / l) * -30; py = anchor.y + (dy / l) * -30;
    } else {
      px = anchor.x; py = anchor.y;
    }
    const t = nearestEnemy(sim, u, e => dist(e, { x: px, y: py }) < 220) || nearestEnemy(sim, u);
    u.attackTarget = t;
    const woundedShield = alliesWithin(sim, u, 110).length >= 2;
    if (u.abilityCd <= 0 && woundedShield) u.abilityRequested = true;
    if (t && dist(u, t) < 60) hold(u, { x: px, y: py }, 4);
    else hold(u, { x: px, y: py }, 8);
    if (t && dist(u, t) <= u.def.attack.range + t.def.radius) u.attackTarget = t;
  },

  healer: (sim, u) => {
    if (retreatIfHurt(sim, u, 0.35)) { u.attackTarget = null; return; }
    const t = nearestEnemy(sim, u);
    const d = t ? dist(u, t) : Infinity;
    const healT = mostWoundedAlly(sim, u, 190);
    u.attackTarget = t && d < u.def.attack.range + 40 ? t : null;
    if (u.abilityCd <= 0 && healT) {
      u.abilityRequested = true;
      sim.setHealTarget(u, healT);
    }
    if (d < 150) {
      hold(u, behindOf(sim, u, u, 100), 15);
    } else if (healT && dist(u, healT) > 160) {
      hold(u, behindOf(sim, u, healT, 60), 12);
    } else {
      hold(u, behindOf(sim, u, allyFrontlineCentroid(sim, u), 70), 25);
    }
  },

  artificer: (sim, u) => {
    if (retreatIfHurt(sim, u)) { u.attackTarget = null; return; }
    const t = nearestEnemy(sim, u);
    u.attackTarget = t && dist(u, t) < u.def.attack.range ? t : null;
    const front = allyFrontlineCentroid(sim, u);
    const totemAlive = sim.devices.some(dv => dv.kind === 'totem' && dv.team === u.team && dv.hp > 0 && dv.owner === u);
    const maxTotems = u.hasUpgrade && u.hasUpgrade('artificer_twin') ? 2 : 1;
    if (u.abilityCd <= 0 && sim.devices.filter(dv => dv.kind === 'totem' && dv.team === u.team).length < maxTotems) {
      u.abilityRequested = true;
      u.moveTarget = { x: front.x, y: front.y };
    } else {
      hold(u, behindOf(sim, u, front, 80), 30);
      if (t) kite(u, t, 110);
    }
  },

  titan: (sim, u) => {
    // Advance on the densest enemy cluster.
    const ec = enemyCentroid(sim, u);
    const t = nearestEnemy(sim, u);
    u.attackTarget = t;
    if (t) {
      const aoeR = u.def.id === 'colossus' ? 130 : 95;
      const crowd = enemiesWithin(sim, u, aoeR);
      if (u.abilityCd <= 0 && crowd.length >= 2) u.abilityRequested = true;
      pursue(u, t, 8);
    } else hold(u, ec, 60);
  },

  caster: (sim, u) => {
    if (retreatIfHurt(sim, u)) { u.attackTarget = null; return; }
    const t = nearestEnemy(sim, u, e => dist(u, e) < u.def.attack.range + 60) || nearestEnemy(sim, u);
    u.attackTarget = t;
    const clump = t ? enemiesWithin(sim, t, 60).length : 0;
    if (u.abilityCd <= 0 && t && clump >= 2) u.abilityRequested = true;
    if (t) {
      kite(u, t, 140);
      const d = dist(u, t);
      if (d > u.def.attack.range * 0.9) pursue(u, t, 10);
      else if (d > 120) strafe(u, t);
    } else hold(u, behindOf(sim, u, { x: sim.W / 2, y: sim.H / 2 }, 80), 40);
  },

  artillery: (sim, u) => {
    if (retreatIfHurt(sim, u)) { u.attackTarget = null; return; }
    const t = nearestEnemy(sim, u) || nearestEnemy(sim, u, () => true);
    u.attackTarget = t;
    if (u.abilityCd <= 0 && t && t.hp > t.maxHp * 0.5 && dist(u, t) < u.def.attack.range) u.abilityRequested = true;
    if (t) {
      kite(u, t, 190);
      if (dist(u, t) > u.def.attack.range * 0.85) pursue(u, t, 20);
      else hold(u, u, 2);
    } else hold(u, behindOf(sim, u, { x: sim.W / 2, y: sim.H / 2 }, 120), 40);
  },

  engineer: (sim, u) => {
    if (retreatIfHurt(sim, u)) { u.attackTarget = null; return; }
    const t = nearestEnemy(sim, u);
    u.attackTarget = t && dist(u, t) < u.def.attack.range ? t : null;
    const mine = sim.devices.filter(dv => dv.kind === 'turret' && dv.owner === u && dv.hp > 0);
    const maxT = u.hasUpgrade && u.hasUpgrade('engineer_nest') ? 2 : 1;
    if (u.abilityCd <= 0 && mine.length < maxT) {
      u.abilityRequested = true;
    }
    if (t) {
      kite(u, t, 100);
      if (dist(u, t) > u.def.attack.range) hold(u, behindOf(sim, u, u, 20), 10);
    } else {
      hold(u, behindOf(sim, u, allyFrontlineCentroid(sim, u), 60), 30);
    }
  },

  disruptor: (sim, u) => {
    if (retreatIfHurt(sim, u)) { u.attackTarget = null; return; }
    const juicy = e => (e.def.category === 'support' || e.def.category === 'commander' ||
      e.def.category === 'specialist' || e.def.category === 'ranged');
    const t = nearestEnemy(sim, u, juicy) || nearestEnemy(sim, u);
    u.attackTarget = t;
    if (u.abilityCd <= 0 && t && juicy(t) && !t.hasStatus('stun')) u.abilityRequested = true;
    if (t) {
      kite(u, t, 120);
      if (dist(u, t) > u.def.attack.range * 0.9) pursue(u, t, 15);
    } else hold(u, { x: sim.W / 2, y: sim.H / 2 }, 60);
  },

  commander: (sim, u) => {
    if (retreatIfHurt(sim, u)) { u.attackTarget = null; return; }
    const t = nearestEnemy(sim, u, e => dist(u, e) < 220);
    u.attackTarget = t || null;
    const friends = alliesWithin(sim, u, 200).length;
    if (u.abilityCd <= 0 && friends >= 2) u.abilityRequested = true;
    const front = allyFrontlineCentroid(sim, u);
    hold(u, behindOf(sim, u, front, 55), 25);
    if (t && dist(u, t) < 60) u.attackTarget = t;
  }
};

export function think(sim, u) {
  u.moveTarget = null; u.abilityRequested = false; u.attackTarget = null;
  const brain = BRAINS[u.def.brain] || BRAINS.brawler;
  brain(sim, u);
  focusFire(sim, u);
  devicePriority(sim, u);
}

// Team coordination: part of the army converges on the squad's prime target
// (the enemy most targeted by living allies) instead of each fighting alone.
export function primeTarget(sim, u) {
  const tally = new Map();
  for (const a of sim.units) {
    if (!a.alive || a.team !== u.team || a === u || a.isDecoy) continue;
    const t = a.attackTarget;
    if (t && t.alive && t.team !== u.team) tally.set(t, (tally.get(t) || 0) + 1);
  }
  let best = null, bestN = 1;
  for (const [e, n] of tally) if (n > bestN) { bestN = n; best = e; }
  return best;
}

function focusFire(sim, u) {
  if (!u.attackTarget || u.brainRng.chance(0.55)) return;
  const prime = primeTarget(sim, u);
  if (!prime || prime === u.attackTarget) return;
  if (dist(u, prime) <= u.def.attack.range + 320) u.attackTarget = prime;
}
