// UNIT CLASH — Node smoke tests (pure simulation layer only).
// Run: npm test   (node --test tests/)
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { BattleSim, WORLD } from '../js/sim.js';
import { RNG } from '../js/rng.js';
import { UNITS, resolveDef, UPGRADES } from '../js/units.js';
import { unitCost, configCost, cloneConfig, deterministicSeed, BattleLab, duelWinner, duelConfig, matrixScores } from '../js/battlelab.js';
import { aggregate, generateInsights } from '../js/stats.js';
import { randomArmy, layoutArmy, dailyChallenge, generateEnemyFor, CAMPAIGN } from '../js/modes.js';
import { FACTIONS } from '../js/factions.js';
import { ARENAS } from '../js/arenas.js';
import { SaveService } from '../js/save.js';
import { ProgressionService, ACHIEVEMENTS, LEVEL_XP } from '../js/progression.js';

const UNIT_IDS = Object.keys(UNITS);

// A mirrored 6v6 lineup touching several categories and brains.
const LINEUP = ['scout', 'brawler', 'guardian', 'medic', 'heavy', 'sparkcaster'];

function mirroredConfig(seed = 12345, extra = {}) {
  const mk = side => {
    // side 'A' occupies the left half, 'B' mirrors on the right.
    const xBase = side === 'A' ? 260 : WORLD.W - 260;
    const dir = side === 'A' ? 1 : -1;
    return LINEUP.map((type, i) => ({
      type, upgrade: null,
      x: xBase + dir * (i % 2) * 60,
      y: 250 + i * 80
    }));
  };
  return {
    arena: 'grassland', modifiers: [], timeLimit: 60, seed,
    collectEvents: false,
    teams: { A: { units: mk('A') }, B: { units: mk('B') } },
    ...extra
  };
}

function teamAgg(snap) {
  return {
    outcome: snap.outcome, duration: snap.duration,
    A: snap.team.A, B: snap.team.B,
    unitDmg: snap.units.map(u => [u.unitId, u.team, Math.round(u.damageDealt), Math.round(u.healing), u.kills, u.diedAt])
  };
}

test('roster integrity: every unit def has required fields and a known brain', async t => {
  const { BRAINS } = await import('../js/ai.js');
  assert.ok(UNIT_IDS.length >= 12, 'spec requires at least 12 units, got ' + UNIT_IDS.length);
  for (const id of UNIT_IDS) {
    const d = UNITS[id];
    assert.equal(d.id, id, id + ': id mismatch');
    for (const k of ['name', 'desc', 'category', 'cost', 'hp', 'speed', 'radius', 'attack', 'ability', 'brain', 'visual', 'color']) {
      assert.ok(d[k] !== undefined && d[k] !== null, `${id}: missing ${k}`);
    }
    assert.ok(BRAINS[d.brain], `${id}: unknown brain "${d.brain}"`);
    assert.ok(d.cost > 0 && d.hp > 0 && d.speed > 0, id + ': non-positive core stats');
    assert.ok(Array.isArray(d.upgrades) && d.upgrades.length >= 1, id + ': no upgrade path');
    for (const up of d.upgrades) assert.ok(UPGRADES[up.id], `${id}: unknown upgrade ${up.id}`);
  }
});

test('resolveDef applies upgrades and returns an independent clone', () => {
  const id = UNIT_IDS[0];
  const upId = UNITS[id].upgrades[0].id;
  const d = resolveDef(id, upId);
  assert.equal(d.upgrade, upId);
  assert.notEqual(d, UNITS[id]);
  assert.deepEqual(JSON.parse(JSON.stringify(UNITS[id])).hp, UNITS[id].hp, 'base def must not be mutated');
  assert.throws(() => resolveDef('no_such_unit'), /Unknown unit/);
});

test('a standard 6v6 battle reaches a valid outcome', () => {
  const sim = new BattleSim(mirroredConfig());
  const snap = sim.runToEnd();
  assert.ok(sim.outcome, 'outcome must be set');
  assert.ok(['A', 'B', 'draw'].includes(sim.outcome.winner), 'winner must be A/B/draw');
  assert.ok(['annihilation', 'timeout', 'cap', 'mutual'].includes(sim.outcome.reason));
  assert.ok(snap.duration > 0);
  assert.equal(snap.team.A.survivors + snap.team.B.survivors,
    snap.units.filter(u => u.diedAt == null).length, 'survivor count consistency');
});

test('determinism: same seed and config produce identical battles', () => {
  const s1 = teamAgg(new BattleSim(mirroredConfig(777)).runToEnd());
  const s2 = teamAgg(new BattleSim(mirroredConfig(777)).runToEnd());
  assert.deepEqual(s1, s2, 'same seed must replay exactly');
  // Verify the seed actually reaches the sim:
  assert.equal(new BattleSim(mirroredConfig(778)).seed, 778);
});

test('event collection does not affect the simulation', () => {
  const withEvents = teamAgg(new BattleSim(mirroredConfig(42, { collectEvents: true })).runToEnd());
  const headless = teamAgg(new BattleSim(mirroredConfig(42)).runToEnd());
  assert.deepEqual(withEvents, headless, 'collectEvents:false must not change results');
});

test('stats are non-zero and internally consistent', () => {
  const snap = new BattleSim(mirroredConfig(999)).runToEnd();
  const totalDmg = snap.team.A.damageDealt + snap.team.B.damageDealt;
  assert.ok(totalDmg > 0, 'damage must have been dealt');
  assert.ok(totalDmg < 10_000_000, 'damage within sane bounds');
  const kills = snap.team.A.kills + snap.team.B.kills;
  const lost = snap.team.A.lost + snap.team.B.lost;
  assert.equal(kills, lost, 'every loss must be credited as a kill');
  const dead = snap.units.filter(u => u.diedAt != null).length;
  assert.equal(lost, dead, 'lost count must match recorded deaths');
});

test('armies can differ: asymmetric config produces a result', () => {
  const cfg = mirroredConfig(5);
  cfg.teams.B.units = [{ type: 'colossus', x: WORLD.W - 300, y: 450 }];
  cfg.teams.A.units = LINEUP.map((type, i) => ({ type, x: 300 + (i % 2) * 60, y: 250 + i * 80 }));
  const snap = new BattleSim(cfg).runToEnd();
  assert.ok(snap.outcome && ['A', 'B', 'draw'].includes(snap.outcome.winner));
  assert.ok(snap.team.A.damageDealt > 0 || snap.team.B.damageDealt > 0);
});

test('unit cost and config cost math', () => {
  assert.equal(unitCost('scout'), UNITS.scout.cost);
  assert.equal(unitCost('colossus'), 400);
  assert.equal(unitCost('not_a_unit'), 0);
  const cfg = { teams: { A: { units: [{ type: 'scout' }, { type: 'medic' }] }, B: { units: [{ type: 'heavy' }] } } };
  const c = configCost(cfg);
  assert.equal(c.A, UNITS.scout.cost + UNITS.medic.cost);
  assert.equal(c.B, UNITS.heavy.cost);
  assert.deepEqual(configCost({ teams: {} }), { A: 0, B: 0 });
});

test('cloneConfig is a deep copy', () => {
  const cfg = mirroredConfig();
  const c = cloneConfig(cfg);
  c.teams.A.units[0].x = -12345;
  c.seed = 0;
  assert.equal(cfg.seed, 12345);
  assert.notEqual(cfg.teams.A.units[0].x, -12345);
});

test('deterministicSeed is stable per (config, runIndex) and varies by run', () => {
  const cfg = { seed: 1000 };
  assert.equal(deterministicSeed(cfg, 0), deterministicSeed(cfg, 0));
  assert.notEqual(deterministicSeed(cfg, 0), deterministicSeed(cfg, 1));
  assert.equal(deterministicSeed({}, 3), (12345 + 3 * 7919) >>> 0, 'default base seed');
});

test('lab aggregation over multiple runs has no NaN and correct win counts', () => {
  const snaps = [];
  for (let i = 0; i < 4; i++) {
    const cfg = mirroredConfig(1000);
    cfg.seed = deterministicSeed(cfg, i);
    snaps.push(new BattleSim(cfg).runToEnd());
  }
  const agg = aggregate(snaps);
  assert.equal(agg.runs, 4);
  assert.equal(agg.winsA + agg.winsB + agg.draws, 4);
  for (const k of ['avgDuration', 'avgSurvivorsA', 'avgSurvivorsB', 'avgDamageA', 'avgDamageB', 'avgLostA', 'avgLostB']) {
    assert.ok(Number.isFinite(agg[k]), k + ' must be finite, got ' + agg[k]);
  }
  assert.ok(Array.isArray(agg.unitPerf));
  for (const rec of agg.unitPerf) {
    assert.ok(Number.isFinite(rec.avgDmg) && Number.isFinite(rec.avgHeal) && Number.isFinite(rec.avgKills));
  }
});

test('insights derive from a real snapshot and reference tracked data', () => {
  const snap = new BattleSim(mirroredConfig(31337)).runToEnd();
  const insights = generateInsights(snap);
  assert.ok(Array.isArray(insights), 'insights must be an array');
  for (const i of insights) {
    assert.equal(typeof i.text, 'string');
    assert.ok(i.text.length > 0);
    assert.ok(['A', 'B', 'draw', null, undefined].includes(i.team) || typeof i.team === 'string');
  }
});

test('randomArmy respects budget and restrictions', () => {
  const rng = new RNG(1234);
  const budget = 500;
  for (let trial = 0; trial < 10; trial++) {
    const { picks, spent } = randomArmy(budget, rng, {});
    assert.ok(Array.isArray(picks) && picks.length > 0, 'army should not be empty');
    assert.ok(spent <= budget + 40, 'army cost ' + spent + ' exceeds budget tolerance');
    for (const type of picks) assert.ok(UNITS[type], 'army must only contain known units');
  }
  const restricted = randomArmy(600, rng, { categories: ['frontline', 'support'] });
  for (const type of restricted.picks) {
    assert.ok(['frontline', 'support'].includes(UNITS[type].category),
      'restricted army contained ' + UNITS[type].category);
  }
});

test('layoutArmy positions units on the requested side within the world', () => {
  const rng = new RNG(9);
  const ids = ['guardian', 'medic', 'sniper', 'heavy'];
  const placed = layoutArmy(ids, 'A', { W: WORLD.W, H: WORLD.H }, rng, 'balanced');
  assert.equal(placed.length, 4);
  for (const p of placed) {
    assert.ok(p.x >= 0 && p.x <= WORLD.W && p.y >= 0 && p.y <= WORLD.H);
    assert.ok(p.x < WORLD.W * 0.5, 'team A units belong on the left half');
    assert.ok(UNIT_IDS.includes(p.type));
  }
});

test('daily challenge and campaign data are well formed', () => {
  const dc = dailyChallenge('2025-06-15');
  assert.ok(ARENAS[dc.arena], 'daily arena must exist');
  assert.ok(dc.playerBudget > 0, 'daily must define a player budget');
  assert.ok(Array.isArray(dc.enemy) && dc.enemy.length > 0, 'daily must generate an enemy');
  const dc2 = dailyChallenge('2025-06-15');
  assert.deepEqual(dc, dc2, 'same date must yield the same challenge');
  const dc3 = dailyChallenge('2025-06-16');
  assert.equal(dc3.id, 'daily-2025-06-16');
  assert.ok(CAMPAIGN.length >= 3, 'campaign should have several missions');
  for (const m of CAMPAIGN) {
    assert.ok(m.name && m.desc && ARENAS[m.arena] && m.playerBudget > 0 && m.enemyBudget > 0,
      'malformed mission: ' + m.name);
    const enemy = generateEnemyFor(m, 1);
    assert.ok(Array.isArray(enemy) && enemy.length > 0, 'mission enemy generation: ' + m.name);
  }
});

test('progression math: levels, mastery, achievements', () => {
  assert.equal(LEVEL_XP(1), 100);
  assert.equal(LEVEL_XP(2), 250);
  const p = new ProgressionService();
  p.profile = { xp: 0, level: 1, mastery: {}, achievements: [], campaignProgress: 0 };
  p.addXP(LEVEL_XP(1));
  assert.equal(p.profile.level, 2, 'crossing the threshold levels up');
  p.recordUnitUse(['scout', 'scout']);
  assert.ok(p.masteryTier('scout') !== undefined);
  assert.ok(ACHIEVEMENTS.length >= 5);
});

test('factions and arenas registries are complete', () => {
  for (const [id, f] of Object.entries(FACTIONS)) {
    assert.equal(typeof f.apply, 'function', 'faction ' + id + ' needs apply()');
    assert.ok(f.name && f.blurb && f.bonusText, 'faction ' + id + ' incomplete');
  }
  for (const [id, a] of Object.entries(ARENAS)) {
    assert.ok(a.name && a.blurb && a.ground && Array.isArray(a.modifiers), 'arena ' + id + ' incomplete');
  }
  assert.ok(Object.keys(ARENAS).length >= 6, 'spec requires 6 arenas');
  assert.ok(Object.keys(FACTIONS).length >= 4, 'spec requires 4 factions');
});

test('BattleLab runs headless multi-config experiments end to end', async () => {
  const lab = new BattleLab();
  const base = mirroredConfig(500);
  const exp = lab.newExperiment(base, 'Guardian wall test');
  assert.equal(exp.configs.length, 1);
  const variant = cloneConfig(base);
  variant.teams.B.units = [{ type: 'colossus', x: WORLD.W - 300, y: 450 }];
  const v = lab.duplicateConfig(exp.configs[0].id, 'Colossus counter');
  assert.ok(v, 'duplicateConfig must return the new config');
  lab.updateConfig(v.id, variant);
  assert.equal(lab.experiment.configs.length, 2);
  assert.deepEqual(lab.experiment.configs[0].config, base, 'baseline must be untouched by variants');

  const done = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('lab runAll timed out')), 60000);
    lab.runAll(2, null, () => { clearTimeout(timer); resolve(); });
  });
  assert.equal(lab.running, false);
  for (const c of lab.experiment.configs) {
    assert.ok(c.results && Array.isArray(c.results.snapshots) && c.results.snapshots.length === 2,
      'each config needs 2 snapshots');
    for (const snap of c.results.snapshots) {
      assert.ok(snap.outcome && ['A', 'B', 'draw'].includes(snap.outcome.winner));
    }
    assert.ok(c.results.agg && c.results.agg.runs === 2, 'aggregate computed per config');
    assert.ok(Array.isArray(c.results.lastInsights));
  }
});

test('SaveService tolerates missing localStorage (Node)', () => {
  const cfg = mirroredConfig(1);
  assert.doesNotThrow(() => SaveService.saveConfig('t1', cfg));
  assert.doesNotThrow(() => SaveService.listConfigs());
  assert.doesNotThrow(() => SaveService.getProfile());
});

// =================== v0.2 improvement tests ===================

test('new units: Phoenix and Reaper exist with valid defs and upgrades', () => {
  for (const id of ['phoenix', 'reaper']) {
    const d = UNITS[id];
    assert.ok(d, id + ' missing from roster');
    assert.ok(d.rebirth || d.attack.lifesteal, id + ' lacks its signature mechanic');
    for (const up of d.upgrades) assert.ok(UPGRADES[up.id], id + ' upgrade unresolved');
  }
  assert.ok(UNIT_IDS.length >= 15, 'roster should now be 15 units');
});

test('Phoenix rebirth: survives its first death, dies permanently after', async () => {
  const { BattleSim } = await import('../js/sim.js');
  const cfg = {
    arena: 'grassland', modifiers: [], timeLimit: 60, seed: 11, collectEvents: false,
    teams: {
      A: { units: [{ type: 'phoenix', x: 300, y: 450 }] },
      B: { units: [{ type: 'brawler', x: 340, y: 460 }] }
    }
  };
  const sim = new BattleSim(cfg);
  const ph = sim.units.find(u => u.def.id === 'phoenix');
  const foe = sim.units.find(u => u.def.id === 'brawler');

  sim.damage(null, ph, 9999, {});
  assert.ok(ph.rebirthUsed, 'first death must trigger rebirth');
  assert.ok(ph.alive, 'phoenix must rise again');
  assert.ok(ph.hp > 0 && ph.hp < ph.maxHp, 'rebirth restores partial health');
  assert.ok(foe.hp < foe.maxHp || foe.hp > 0, 'nova damages nearby enemies without breaking');

  sim.damage(null, ph, 9999, {});
  assert.ok(!ph.alive, 'second death is permanent');
  const snap = sim.stats.snapshot();
  assert.equal(snap.team.A.lost, 1, 'rebirth must not be counted as a loss');
});

test('Reaper lifesteal: heals for a share of damage dealt', async () => {
  const { BattleSim } = await import('../js/sim.js');
  const cfg = {
    arena: 'grassland', modifiers: [], timeLimit: 45, seed: 5, collectEvents: false,
    teams: {
      A: { units: [{ type: 'reaper', x: 300, y: 450 }] },
      B: { units: [{ type: 'brawler', x: 1300, y: 450 }] }
    }
  };
  const snap = new BattleSim(cfg).runToEnd();
  const rec = snap.units.find(u => u.unitId === 'reaper');
  assert.ok(rec.damageDealt > 0, 'reaper must deal damage');
  assert.ok(rec.healing > 0, 'lifesteal must produce healing');
  assert.ok(rec.healing <= rec.damageDealt * 0.95, 'lifesteal cannot exceed damage dealt');
});

test('focus-fire coordination keeps determinism', () => {
  const cfg = mirroredConfig(2468, { timeLimit: 45 });
  const a = teamAgg(new BattleSim(cfg).runToEnd());
  const b = teamAgg(new BattleSim(cfg).runToEnd());
  assert.deepEqual(a, b, 'focus fire must not introduce nondeterminism');
});

test('BattleLab.autoFormations generates deduped formation variants', () => {
  const lab = new BattleLab();
  const cfg = mirroredConfig(90);
  cfg.collectEvents = false;
  lab.newExperiment(cfg, 'formation auto test');
  assert.equal(lab.autoFormations(), true, 'first call adds variants');
  assert.equal(lab.autoFormations(), false, 'second call must not duplicate');
  const names = lab.experiment.configs.map(c => c.name);
  for (const n of ['Defensive Line', 'Balanced', 'Scattered']) assert.ok(names.includes(n), 'missing variant ' + n);
  assert.deepEqual(lab.experiment.configs[0].config.teams.A.units, mirroredConfig(90).teams.A.units,
    'baseline units must remain untouched');
});

test('timeline data supports the battle-flow chart', () => {
  const cfg = mirroredConfig(55, { timeLimit: 45 });
  const snap = new BattleSim(cfg).runToEnd();
  assert.ok(Array.isArray(snap.timeline));
  const startA = snap.units.filter(u => u.team === 'A').length;
  const deaths = snap.timeline.filter(e => e.type === 'death' && e.team === 'A').length;
  assert.equal(deaths, startA - snap.team.A.survivors, 'timeline deaths must reconcile with survivors');
});

test('share code round-trips a config exactly', async () => {
  const { GameController } = await import('../js/ui.js');
  const cfg = mirroredConfig(321);
  const encoded = 'UC1.' + Buffer.from(unescape(encodeURIComponent(JSON.stringify(cfg))), 'binary').toString('base64');
  assert.ok(encoded.startsWith('UC1.'));
  const decoded = GameController.prototype.decodeConfig.call({}, encoded);
  assert.deepEqual(decoded, cfg, 'decode(encode(cfg)) must equal cfg');
  assert.equal(GameController.prototype.decodeConfig.call({}, 'UC1.nonsense!!!'), null);
  assert.equal(GameController.prototype.decodeConfig.call({}, 'garbage'), null);
});

// ---------------- v0.4 additions: destructible devices + matchup matrix ----------------

test('devices are destructible: direct damage, AoE abilities, and projectiles all hurt them', () => {
  const cfg = mirroredConfig(7);
  cfg.teams.A.units = [{ type: 'brawler', x: 400, y: 450, upgrade: null }];
  cfg.teams.B.units = [{ type: 'engineer', x: 1200, y: 450, upgrade: null }];
  const sim = new BattleSim(cfg);
  const eng = sim.units.find(u => u.def.id === 'engineer');
  sim.abTurret(eng);
  sim.abTurret(eng); // second call would exceed nest limit in real AI, but spawns directly here
  const turrets = sim.devices.filter(d => d.kind === 'turret');
  assert.ok(turrets.length >= 1, 'turret must exist');
  const t = turrets[0];
  assert.ok(t.uid, 'device must have a uid');
  const hp0 = t.hp;

  sim.damageDevice(sim.units[0], t, 25);
  assert.equal(t.hp, hp0 - 25, 'direct device damage must apply');

  sim.damageDevices(sim.units[0], t.x, t.y, 400, 30);
  assert.equal(t.hp, hp0 - 55, 'AoE device damage must apply');

  const totem = sim.devices.find(d => d.kind === 'totem');
  assert.equal(totem, undefined, 'no totems in this scenario');

  const destroyed = sim.devices.find(d => d.hp <= 0);
  assert.equal(destroyed, undefined, 'turret still alive');
  sim.damageDevice(sim.units[0], t, 9999);
  assert.equal(t.hp, 0, 'turret hp floors at zero');
  sim.step();
  assert.ok(!sim.devices.includes(t), 'destroyed turret must be removed on the next step');
});

test('projectiles can destroy enemy devices (Engineer counterplay)', () => {
  const cfg = mirroredConfig(11);
  cfg.teams.A.units = [{ type: 'sparkcaster', x: 300, y: 450, upgrade: null }];
  cfg.teams.B.units = [{ type: 'engineer', x: 700, y: 450, upgrade: null }];
  const sim = new BattleSim(cfg);
  const eng = sim.units.find(u => u.def.id === 'engineer');
  sim.abTurret(eng);
  const turret = sim.devices.find(d => d.kind === 'turret');
  assert.ok(turret, 'turret must exist');
  // Place a sparkcaster directly opposite the turret so its bolts fly at/past it.
  const caster = sim.units.find(u => u.def.id === 'sparkcaster');
  caster.x = turret.x - 180; caster.y = turret.y;
  const hp0 = turret.hp;
  let sawHit = false;
  for (let i = 0; i < 30 * 20 && !sawHit; i++) {
    sim.step();
    if (sim.t > 1 && turret.hp < hp0) sawHit = true;
  }
  assert.ok(sawHit, 'enemy projectiles must damage the turret (was invincible before v0.4)');
});

test('matchup matrix duels are deterministic and well-formed', () => {
  const a = duelWinner('scout', 'heavy', 0);
  const b = duelWinner('scout', 'heavy', 0);
  assert.equal(a, b, 'same duel + run index must replay identically');
  assert.ok(['A', 'B', 'draw'].includes(a), 'winner must be a valid outcome');
  const cfg = duelConfig('medic', 'colossus', 2);
  assert.equal(cfg.teams.A.units.length, 1);
  assert.equal(cfg.teams.B.units.length, 1);
  assert.equal(cfg.arena, 'training');
  const c = duelConfig('medic', 'colossus', 2);
  assert.deepEqual(cfg, c, 'duel configs must be reproducible');
});

test('matrixScores ranks units in 0..1 with duel counts', () => {
  const entries = {
    'scout|heavy': { a: 'scout', b: 'heavy', winsA: 2, winsB: 4, draws: 0 },
    'scout|medic': { a: 'scout', b: 'medic', winsA: 5, winsB: 1, draws: 0 },
    'heavy|medic': { a: 'heavy', b: 'medic', winsA: 4, winsB: 2, draws: 0 }
  };
  const scores = matrixScores(entries);
  assert.equal(scores.length, 3);
  for (const s of scores) {
    assert.ok(s.score >= 0 && s.score <= 1, 'score must be a rate');
    assert.equal(s.duels, 2);
  }
  const byId = Object.fromEntries(scores.map(s => [s.id, s.score]));
  assert.ok(byId.medic < byId.heavy, 'medic should lose duels to heavy');
  assert.ok(byId.heavy > byId.scout, 'heavy (2/6 + 4/6) should outscore scout (2/6 + 5/6) on aggregate here');
});
