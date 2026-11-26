// Game modes share one battle configuration format.
import { RNG, hashSeed } from './rng.js';
import { UNIT_LIST, UNITS } from './units.js';
import { ARENAS } from './arenas.js';

// ---- Random army generator (used by sandbox dice button + Battle Lab) ----
export function randomArmy(budget, rng, restrictions = {}) {
  let pool = UNIT_LIST.filter(u => {
    if (restrictions.categories && !restrictions.categories.includes(u.category)) return false;
    if (restrictions.exclude && restrictions.exclude.includes(u.id)) return false;
    if (restrictions.maxCost && u.cost > restrictions.maxCost) return false;
    return true;
  });
  if (!pool.length) pool = UNIT_LIST;
  const picks = [];
  let spent = 0;
  let guard = 0;
  while (spent < budget && guard++ < 200) {
    const u = rng.pick(pool);
    if (spent + u.cost > budget + 40) continue;
    picks.push(u.id);
    spent += u.cost;
  }
  return { picks, spent };
}

// Generate positions for a list of unit ids on one half of the field.
export function layoutArmy(unitIds, side, sim, rng, style = 'balanced') {
  const W = sim.W, H = sim.H;
  const dir = side === 'A' ? 1 : -1;
  const baseX = side === 'A' ? W * 0.18 : W * 0.82;
  const spread = style === 'scattered' ? 0.9 : style === 'defensive' ? 0.45 : 0.65;
  const cols = Math.max(1, Math.ceil(Math.sqrt(unitIds.length * 1.6)));
  const units = [];
  const byCat = {};
  for (const id of unitIds) {
    const cat = UNITS[id].category;
    (byCat[cat] || (byCat[cat] = [])).push(id);
  }
  // front categories toward center
  const order = ['frontline', 'heavy', 'agile', 'specialist', 'ranged', 'support', 'commander'];
  const flat = [];
  for (const cat of order) if (byCat[cat]) flat.push(...byCat[cat]);
  const orderedSet = new Set(flat);
  for (const ids of Object.values(byCat)) for (const id of ids) if (!orderedSet.has(id)) flat.push(id);

  flat.forEach((id, i) => {
    const row = Math.floor(i / cols);
    const col = i % cols;
    const rowCount = Math.min(cols, flat.length - row * cols);
    const x = baseX + dir * row * 70 + rng.range(-14, 14);
    const y = H / 2 + (col - (rowCount - 1) / 2) * (110 * spread) + rng.range(-10, 10);
    units.push({ type: id, x: clamp(x, 30, W - 30), y: clamp(y, 30, H - 30), upgrade: null });
  });
  return units;
}

export function generateEnemyFor(mission, seed) {
  const rng = new RNG(seed);
  const arenaSim = { W: 1600, H: 900 };
  const { picks } = randomArmy(mission.enemyBudget, rng, mission.restrictions || {});
  return layoutArmy(picks, 'B', arenaSim, rng, mission.style || 'balanced');
}

// ---- Campaign: each stage teaches one strategic idea ----
export const CAMPAIGN = [
  {
    id: 'c1', name: 'First Steps', arena: 'training', playerBudget: 400, enemyBudget: 380,
    desc: 'Learn the basics: win a small skirmish. Place melee units in front, ranged behind.',
    tip: 'Brawlers soak damage while Spark Casters deal it.'
  },
  {
    id: 'c2', name: 'The Wall', arena: 'grassland', playerBudget: 500, enemyBudget: 480,
    desc: 'The enemy fields heavy shields. Bouncing bolts and cleaves punish clumped formations.',
    tip: 'Spark Caster bolts bounce between grouped units.'
  },
  {
    id: 'c3', name: 'Sniper Alley', arena: 'desert', playerBudget: 550, enemyBudget: 530,
    desc: 'Enemy Longshots rule a long open field. Close the distance fast — or outrange them.',
    tip: 'Scouts and Tricksters can reach the backline quickly.'
  },
  {
    id: 'c4', name: 'The Colossus', arena: 'industrial', playerBudget: 600, enemyBudget: 600,
    desc: 'One Colossus leads the enemy army. Nearly unkillable frontally — kite it, disrupt it, win the sides.',
    tip: 'Disruptor + kiting ranged units melt big targets.'
  },
  {
    id: 'c5', name: 'Full Battle', arena: 'rooftop', playerBudget: 800, enemyBudget: 800,
    desc: 'Everything at once. Compose a balanced army: frontline, sustain, ranged and a Commander.',
    tip: 'Commander auras multiply everything you already do well.'
  }
];

// ---- Challenge of the Day: deterministic from the date ----
export function dailyChallenge(dateStr) {
  const seed = hashSeed('daily-' + dateStr);
  const rng = new RNG(seed);
  const arenaIds = Object.keys(ARENAS);
  const arena = arenaIds[rng.int(0, arenaIds.length - 1)];
  const budget = rng.pick([350, 400, 450, 500]);
  const categoryKeys = ['frontline', 'heavy', 'agile', 'support', 'ranged', 'specialist', 'commander'];
  const oneCat = rng.chance(0.5);
  const allowedCats = oneCat ? [categoryKeys[rng.int(0, 6)]] : categoryKeys;
  const restrictions = { categories: allowedCats };
  const enemy = generateEnemyFor(
    { enemyBudget: budget + rng.pick([-50, 0, 50, 100]), restrictions: {}, style: rng.pick(['defensive', 'balanced', 'scattered']) },
    seed ^ 0x9e3779b9
  );
  return {
    id: 'daily-' + dateStr,
    name: 'Challenge of the Day — ' + dateStr,
    desc: `Budget ${budget}. ${oneCat ? `Only ${allowedCats[0]} units allowed.` : 'Any units allowed.'} Arena: ${ARENAS[arena].name}.`,
    arena, playerBudget: budget, enemy, modifiers: ARENAS[arena].modifiers,
    restrictions, seed: seed ^ 0x5bf03635
  };
}

function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
