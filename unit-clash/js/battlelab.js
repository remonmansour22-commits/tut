// ============================================================
// BATTLE LAB — experiment engine + headless multi-run scheduler.
// Runs simulations in background slices so the main game never
// freezes. All randomness is seeded and reproducible.
// ============================================================

import { BattleSim, WORLD } from './sim.js';
import { aggregate, generateInsights } from './stats.js';
import { SaveService } from './save.js';
import { UNITS } from './units.js';
import { layoutArmy } from './modes.js';
import { RNG, hashSeed } from './rng.js';

let EXP_SEQ = 1;
let CFG_SEQ = 1;
const UNIT_COST = Object.fromEntries(Object.entries(UNITS).map(([k, v]) => [k, v.cost]));

export function unitCost(unitId) { return UNIT_COST[unitId] || 0; }
export function cloneConfig(config) { return JSON.parse(JSON.stringify(config)); }

// Every run of a config uses a distinct but reproducible seed, so
// "10 runs" always means the same 10 battles for the same config.
export function deterministicSeed(cfg, runIndex) {
  const base = typeof cfg.seed === 'number' ? cfg.seed : 12345;
  return (base + runIndex * 7919) >>> 0;
}

// ---- Matchup Matrix: deterministic headless 1v1 round-robin ----
export function duelConfig(idA, idB, runIndex) {
  const y = WORLD.H / 2 + ((runIndex % 3) - 1) * 90;
  return {
    arena: 'training', modifiers: [], timeLimit: 45,
    seed: (hashSeed(idA + '|' + idB) + runIndex * 7919) >>> 0,
    collectEvents: false,
    teams: {
      A: { units: [{ type: idA, x: WORLD.W * 0.3, y, upgrade: null }] },
      B: { units: [{ type: idB, x: WORLD.W * 0.7, y, upgrade: null }] }
    }
  };
}

export function duelWinner(idA, idB, runIndex) {
  const sim = new BattleSim(duelConfig(idA, idB, runIndex));
  sim.runToEnd();
  return sim.outcome.winner;
}

// Per-unit overall 1v1 strength from a completed matrix (0..1 average win rate).
export function matrixScores(entries) {
  const tally = new Map();
  for (const e of Object.values(entries)) {
    const n = e.winsA + e.winsB + e.draws || 1;
    const wa = (e.winsA + e.draws * 0.5) / n;
    const wb = (e.winsB + e.draws * 0.5) / n;
    tally.set(e.a, (tally.get(e.a) || []).concat(wa));
    tally.set(e.b, (tally.get(e.b) || []).concat(wb));
  }
  return [...tally.entries()]
    .map(([id, rates]) => ({
      id, name: UNITS[id] ? UNITS[id].name : id,
      score: rates.reduce((s, r) => s + r, 0) / rates.length,
      duels: rates.length
    }))
    .sort((x, y) => y.score - x.score);
}

export function configCost(config) {
  const total = { A: 0, B: 0 };
  for (const t of ['A', 'B']) {
    for (const u of (config.teams?.[t]?.units || [])) total[t] += unitCost(u.type);
  }
  return total;
}

export class BattleLab {
  constructor(onDirty) {
    this.onDirty = onDirty || (() => {});
    this.experiment = null;
    this.running = false;
    this.progress = { done: 0, total: 0 };
    this.matrix = null;
    this.matrixRunning = false;
  }

  newExperiment(baseConfig, name = 'Untitled Experiment') {
    this.experiment = {
      id: 'exp-' + Date.now() + '-' + (EXP_SEQ++),
      name,
      notes: '',
      created: Date.now(),
      configs: [{
        id: 'cfg-' + (CFG_SEQ++),
        name: 'Baseline',
        config: cloneConfig(baseConfig),
        results: null
      }]
    };
    this.persist();
    return this.experiment;
  }

  loadExperiment(exp) {
    this.experiment = exp;
    this.onDirty();
  }

  duplicateConfig(cfgId, newName) {
    const exp = this.experiment;
    const src = exp.configs.find(c => c.id === cfgId);
    if (!src) return null;
    const copy = {
      id: 'cfg-' + (CFG_SEQ++),
      name: newName || src.name + ' (variant)',
      config: cloneConfig(src.config),
      results: null
    };
    exp.configs.push(copy);
    this.persist();
    return copy;
  }

  removeConfig(cfgId) {
    const exp = this.experiment;
    if (exp.configs.length <= 1) return;
    exp.configs = exp.configs.filter(c => c.id !== cfgId);
    this.persist();
  }

  updateConfig(cfgId, config, name) {
    const c = this.experiment.configs.find(c => c.id === cfgId);
    if (!c) return;
    if (config) c.config = cloneConfig(config);
    if (name) c.name = name;
    c.results = null;
    this.persist();
  }

  setMeta(name, notes) {
    if (name != null) this.experiment.name = name;
    if (notes != null) this.experiment.notes = notes;
    this.persist();
  }

  // Synergy scan: for every unit type, create a variant of the baseline with a
  // ~fixed added budget of that unit clustered behind the army. Running the
  // experiment then shows which addition improves the win rate most per cost.
  synergyScan(addedBudget = 200) {
    const exp = this.experiment;
    if (!exp || !exp.configs.length) return 0;
    const base = exp.configs[0];
    const unitsA = base.config.teams?.A?.units || [];
    if (!unitsA.length) return 0;
    let cx = 0, cy = 0;
    for (const u of unitsA) { cx += u.x; cy += u.y; }
    cx /= unitsA.length; cy /= unitsA.length;
    const side = cx < WORLD.W / 2 ? -1 : 1;
    let added = 0;
    for (const id of Object.keys(UNITS)) {
      const def = UNITS[id];
      if (def.cost > addedBudget) continue;
      const copies = Math.max(1, Math.min(6, Math.floor(addedBudget / def.cost)));
      const name = '+' + copies + ' ' + def.name + ' (+' + (def.cost * copies) + ')';
      if (exp.configs.some(c => c.name === name)) continue;
      const copy = cloneConfig(base.config);
      for (let i = 0; i < copies; i++) {
        const x = Math.max(40, Math.min(WORLD.W - 40, cx + side * 70));
        const y = Math.max(40, Math.min(WORLD.H - 40, cy + (i - (copies - 1) / 2) * 46));
        copy.teams.A.units.push({ type: id, x, y, upgrade: null });
      }
      exp.configs.push({ id: 'cfg-' + (CFG_SEQ++), name, config: copy, results: null });
      added++;
    }
    if (added) this.persist();
    return added;
  }

  // Formation Laboratory shortcut: generate defensive/balanced/scattered
  // re-positionings of the baseline army so formation effects can be compared.
  autoFormations() {
    const exp = this.experiment;
    if (!exp || !exp.configs.length) return false;
    const base = exp.configs[0];
    const ids = (base.config.teams?.A?.units || []).map(u => u.type);
    if (!ids.length) return false;
    const styles = [['Defensive Line', 'defensive'], ['Balanced', 'balanced'], ['Scattered', 'scattered']];
    const rng = new RNG(4242);
    let added = 0;
    for (const [name, style] of styles) {
      if (exp.configs.some(c => c.name === name)) continue;
      const copy = cloneConfig(base.config);
      copy.teams.A.units = layoutArmy(ids, 'A', { W: WORLD.W, H: WORLD.H }, rng, style);
      exp.configs.push({ id: 'cfg-' + (CFG_SEQ++), name, config: copy, results: null });
      added++;
    }
    if (added) this.persist();
    return added > 0;
  }

  persist() {
    if (this.experiment) SaveService.saveExperiment(this.experiment);
    this.onDirty();
  }

  // Headless multi-run. Chunked so the browser stays responsive.
  runAll(runsPerConfig, onProgress, onDone) {
    if (this.running || !this.experiment) return false;
    const exp = this.experiment;
    const queue = [];
    for (const c of exp.configs) {
      c.results = null;
      for (let i = 0; i < runsPerConfig; i++) queue.push({ c, i });
    }
    this.running = true;
    this.progress = { done: 0, total: queue.length };
    const self = this;
    let idx = 0;

    function chunk() {
      const start = performance.now();
      while (idx < queue.length && performance.now() - start < 30) {
        const { c, i } = queue[idx++];
        const config = cloneConfig(c.config);
        config.seed = deterministicSeed(config, i);
        config.collectEvents = false;
        const sim = new BattleSim(config);
        const snap = sim.runToEnd();
        c.results = c.results || { runs: 0, snapshots: [] };
        c.results.snapshots.push(snap);
        c.results.runs++;
        c.results.agg = aggregate(c.results.snapshots);
        c.results.lastSnapshot = snap;
        c.results.lastInsights = generateInsights(snap);
        self.progress.done = idx;
      }
      if (onProgress) onProgress(self.progress, queue[idx] ? queue[idx].c : null);
      if (idx < queue.length) {
        setTimeout(chunk, 0);
      } else {
        self.running = false;
        self.persist();
        if (onDone) onDone();
      }
    }
    setTimeout(chunk, 0);
    return true;
  }

  // Matchup Matrix: headless 1v1 round-robin. Chunked like runAll so the
  // browser stays responsive. Optional opts.ids limits the roster (tests).
  runMatrix(runsPerPair, opts = {}, onProgress, onDone) {
    if (this.matrixRunning) return false;
    const ids = opts.ids || Object.keys(UNITS);
    const runs = Math.max(1, Math.min(20, runsPerPair | 0 || 6));
    const pairs = [];
    for (let i = 0; i < ids.length; i++) {
      for (let j = i + 1; j < ids.length; j++) pairs.push([ids[i], ids[j]]);
    }
    if (!pairs.length) return false;
    this.matrixRunning = true;
    const entries = {};
    const self = this;
    let pi = 0, ri = 0;

    function chunk() {
      const start = performance.now();
      while (pi < pairs.length && performance.now() - start < 30) {
        const [a, b] = pairs[pi];
        const w = duelWinner(a, b, ri);
        const key = a + '|' + b;
        const e = entries[key] || (entries[key] = { a, b, winsA: 0, winsB: 0, draws: 0 });
        if (w === 'A') e.winsA++; else if (w === 'B') e.winsB++; else e.draws++;
        ri++;
        if (ri >= runs) { ri = 0; pi++; }
      }
      if (onProgress) onProgress({ done: pi, total: pairs.length, runs });
      if (pi < pairs.length) {
        setTimeout(chunk, 0);
      } else {
        self.matrixRunning = false;
        self.matrix = { runs, entries, computedAt: Date.now(), ids };
        if (onDone) onDone(self.matrix);
      }
    }
    setTimeout(chunk, 0);
    return true;
  }
}
