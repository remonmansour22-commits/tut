// ============================================================
// UNIT REGISTRY — configuration-driven unit definitions.
// Adding a unit = add one entry here + (optionally) a brain in
// ai.js and an ability implementation in abilities.js.
// ============================================================

export const CATEGORIES = {
  frontline: { id: 'frontline', name: 'Frontline', color: '#e8c46b', desc: 'Holds ground and protects allies.' },
  heavy: { id: 'heavy', name: 'Heavy', color: '#d97b5f', desc: 'Slow, durable, devastating.' },
  agile: { id: 'agile', name: 'Agile', color: '#7ee0a3', desc: 'Speed, mobility, opportunism.' },
  support: { id: 'support', name: 'Support', color: '#7ec8e3', desc: 'Healing, shields and utility.' },
  ranged: { id: 'ranged', name: 'Ranged', color: '#c77dff', desc: 'Fights from a distance.' },
  specialist: { id: 'specialist', name: 'Specialist', color: '#f0a35e', desc: 'Unusual mechanics, big strategic impact.' },
  commander: { id: 'commander', name: 'Commander', color: '#f2e27a', desc: 'Empowers nearby allies.' }
};

// Upgrade definitions are referenced by id inside unit entries.
// apply(d) mutates a *clone* of the unit def when the upgrade is selected.
export const UPGRADES = {
  scout_phantom: { id: 'scout_phantom', name: 'Phantom Step', reqLevel: 2, desc: 'Dash leaves a short-lived decoy and grants 0.6s of untargetable speed.' },
  scout_berserk: { id: 'scout_berserk', name: 'Bloodrush', reqLevel: 2, desc: 'Attacks grant stacking +12% speed and +8% damage for 3s.' },
  guardian_bulwark: { id: 'guardian_bulwark', name: 'Greater Bulwark', reqLevel: 3, desc: 'Bulwark radius +50%, shields 40% more.' },
  guardian_react: { id: 'guardian_react', name: 'Reactive Plating', reqLevel: 3, desc: 'Reflects 20% of melee damage taken back at attackers.' },
  brawler_quake: { id: 'brawler_quake', name: 'Quake Cleave', reqLevel: 3, desc: 'Cleave also slows enemies hit by 35% for 1.5s.' },
  brawler_momentum: { id: 'brawler_momentum', name: 'Momentum', reqLevel: 3, desc: 'Each consecutive hit on the same target deals +15% damage (max +60%).' },
  medic_triage: { id: 'medic_triage', name: 'Triage Field', reqLevel: 3, desc: 'Healing pulses also cleanse stuns and slows on allies.' },
  medic_bloom: { id: 'medic_bloom', name: 'Bloom Ward', reqLevel: 3, desc: 'Healed allies gain a small regen for 2s.' },
  heavy_seismic: { id: 'heavy_seismic', name: 'Seismic Ring', reqLevel: 4, desc: 'Slam shockwave radius +60% and briefly stuns.' },
  heavy_bulwark2: { id: 'heavy_bulwark2', name: 'Reinforced Frame', reqLevel: 4, desc: '+25% HP, but move 15% slower.', apply(d) { d.hp = Math.round(d.hp * 1.25); d.speed = Math.round(d.speed * 0.9); } },
  caster_storm: { id: 'caster_storm', name: 'Storm Coils', reqLevel: 3, desc: 'Bolts bounce +2 times and chain slightly further.' },
  caster_overload: { id: 'caster_overload', name: 'Overload', reqLevel: 3, desc: 'Overcharge also fires a ring of 6 mini-bolts.' },
  sniper_pierceup: { id: 'sniper_pierceup', name: 'Rail Core', reqLevel: 3, desc: 'Focused Shot pierces all enemies in a line.' },
  sniper_deadeye: { id: 'sniper_deadeye', name: "Deadeye", reqLevel: 3, desc: 'Attacks against full-HP targets deal +50% damage.' },
  engineer_upgradeturret: { id: 'engineer_upgradeturret', name: 'Hive Turret', reqLevel: 3, desc: 'Turrets gain +40% fire rate and shoot splitting sparks.' },
  engineer_nest: { id: 'engineer_nest', name: 'Scrap Nest', reqLevel: 3, desc: 'Can deploy a second, weaker turret.' },
  disruptor_blackout: { id: 'disruptor_blackout', name: 'Blackout', reqLevel: 3, desc: 'Static Leash silences for 3s and disables shields it touches.' },
  disruptor_feedback: { id: 'disruptor_feedback', name: 'Feedback Loop', reqLevel: 3, desc: 'Silenced enemies take +15% damage from all sources.' },
  commander_phoenix: { id: 'commander_phoenix', name: 'Rally Banner', reqLevel: 4, desc: 'Battle Cry also heals allies in radius for 25 HP.' },
  commander_warlord: { id: 'commander_warlord', name: 'Warlord', reqLevel: 4, desc: 'Aura bonus increased to +25% damage and +15% speed.' },
  trickster_mirage: { id: 'trickster_mirage', name: 'Mirage', reqLevel: 3, desc: 'Decoys explode on death for small AoE damage.' },
  trickster_shadow: { id: 'trickster_shadow', name: 'Shadow Fang', reqLevel: 3, desc: 'Attacks from behind deal +60% damage.' },
  artificer_grove: { id: 'artificer_grove', name: 'Grove Engine', reqLevel: 3, desc: 'Totems also grant a move-speed aura.' },
  artificer_twin: { id: 'artificer_twin', name: 'Twin Works', reqLevel: 3, desc: 'Can maintain two totems at once.' },
  phoenix_ember: { id: 'phoenix_ember', name: 'Ember Wake', reqLevel: 3, desc: 'Rebirth nova is larger and sets enemies ablaze, slowing them.' },
  phoenix_solar: { id: 'phoenix_solar', name: 'Solar Grace', reqLevel: 3, desc: 'Abilities recover 25% faster and the rebirth restores more health.', apply(d) { d.abilityRateMul = (d.abilityRateMul || 1) * 1.25; } },
  reaper_bloodmoon: { id: 'reaper_bloodmoon', name: 'Bloodmoon', reqLevel: 3, desc: 'Life harvest increased to 90% of damage dealt.', apply(d) { d.attack.lifesteal = 0.9; } },
  reaper_deathwing: { id: 'reaper_deathwing', name: 'Deathwing', reqLevel: 3, desc: 'Attacks against enemies below 35% health deal +60% damage.' },
  colossus_meteor: { id: 'colossus_meteor', name: 'Meteor Plating', reqLevel: 5, desc: 'Sweep throws debris that rains down on enemies.' },
  colossus_titan: { id: 'colossus_titan', name: 'Titanheart', reqLevel: 5, desc: 'Below 40% HP, gains 30% damage reduction and clears slows.' }
};

function U(id) { return UPGRADES[id]; }

export const UNITS = {
  scout: {
    id: 'scout', name: 'Scout', category: 'agile', faction: 'wildgrove',
    cost: 45, hp: 65, speed: 165, radius: 9, armor: 0,
    attack: { range: 30, damage: 9, cooldown: 0.55, type: 'melee', windup: 0.12, knockback: 40 },
    ability: { name: 'Dash Strike', cooldown: 6, desc: 'Blitzes toward a target; next hit is a guaranteed critical.' },
    brain: 'skirmisher',
    visual: { shape: 'humanoid', size: 0.85, weapon: 'dagger', head: 'antenna' },
    color: '#7ee0a3', accent: '#2f7a4d',
    desc: 'Fast opportunist. Hunts isolated and backline units, then vanishes.',
    upgrades: [U('scout_phantom'), U('scout_berserk')]
  },
  brawler: {
    id: 'brawler', name: 'Brawler', category: 'frontline', faction: 'vanguard',
    cost: 80, hp: 135, speed: 95, radius: 11, armor: 0.05,
    attack: { range: 34, damage: 17, cooldown: 0.9, type: 'melee', windup: 0.18, knockback: 90 },
    ability: { name: 'Cleave', cooldown: 7, desc: 'A wide swing hitting every enemy in front for 150% damage.' },
    brain: 'brawler',
    visual: { shape: 'humanoid', size: 1.05, weapon: 'axe', head: 'band' },
    color: '#e8c46b', accent: '#8f6b2a',
    desc: 'Reliable close-range fighter. Wins most trades, struggles against crowds of ranged.',
    upgrades: [U('brawler_quake'), U('brawler_momentum')]
  },
  guardian: {
    id: 'guardian', name: 'Guardian', category: 'frontline', faction: 'vanguard',
    cost: 90, hp: 175, speed: 85, radius: 12, armor: 0.12,
    attack: { range: 34, damage: 12, cooldown: 1.0, type: 'melee', windup: 0.2, knockback: 70 },
    ability: { name: 'Bulwark', cooldown: 9, desc: 'Shields all allies within 110px, absorbing 45 damage each for 4s.' },
    brain: 'guardian',
    visual: { shape: 'bulky', size: 1.1, weapon: 'shield', head: 'crest' },
    color: '#6fa8dc', accent: '#2f5d8a',
    desc: 'Protects the battle line. Intercepts enemies closing on fragile allies.',
    upgrades: [U('guardian_bulwark'), U('guardian_react')]
  },
  medic: {
    id: 'medic', name: 'Medic', category: 'support', faction: 'wildgrove',
    cost: 100, hp: 80, speed: 100, radius: 10, armor: 0,
    attack: { range: 120, damage: 6, cooldown: 1.1, type: 'projectile', projectile: 'sap', windup: 0.2, knockback: 20 },
    ability: { name: 'Heal Beam', cooldown: 2.2, desc: 'Channels healing to the most wounded ally in 170px: 26 HP.' },
    brain: 'healer',
    visual: { shape: 'robed', size: 0.95, weapon: 'staff', head: 'hood' },
    color: '#8fce6f', accent: '#3e7a35',
    desc: 'Keeps the line alive. Nearly defenseless if caught alone.',
    upgrades: [U('medic_triage'), U('medic_bloom')]
  },
  heavy: {
    id: 'heavy', name: 'Juggernaut', category: 'heavy', faction: 'vanguard',
    cost: 150, hp: 330, speed: 62, radius: 15, armor: 0.15,
    attack: { range: 42, damage: 28, cooldown: 1.5, type: 'melee', windup: 0.3, knockback: 160 },
    ability: { name: 'Ground Slam', cooldown: 8, desc: 'Slams the earth: 34 damage + heavy knockback to everything within 95px.' },
    brain: 'titan',
    visual: { shape: 'bulky', size: 1.35, weapon: 'hammer', head: 'helm' },
    color: '#d97b5f', accent: '#8a3f2a',
    desc: 'An advancing wall. Punishes clumped enemies, easy to kite.',
    upgrades: [U('heavy_seismic'), U('heavy_bulwark2')]
  },
  sparkcaster: {
    id: 'sparkcaster', name: 'Spark Caster', category: 'ranged', faction: 'prism',
    cost: 110, hp: 75, speed: 88, radius: 10, armor: 0,
    attack: { range: 235, damage: 14, cooldown: 1.25, type: 'projectile', projectile: 'bounce', windup: 0.25, knockback: 25, bounce: 2 },
    ability: { name: 'Overcharge', cooldown: 9, desc: 'Next bolt bounces 5 times and deals +50% damage.' },
    brain: 'caster',
    visual: { shape: 'robed', size: 1.0, weapon: 'coil', head: 'visor' },
    color: '#c77dff', accent: '#6a2f9e',
    desc: 'Bouncing energy bolts excel against tight formations. Fragile alone.',
    upgrades: [U('caster_storm'), U('caster_overload')]
  },
  sniper: {
    id: 'sniper', name: 'Longshot', category: 'ranged', faction: 'scrapworks',
    cost: 120, hp: 65, speed: 80, radius: 9, armor: 0,
    attack: { range: 400, damage: 70, cooldown: 2.7, type: 'projectile', projectile: 'rail', windup: 0.45, knockback: 60, crit: 0.2 },
    ability: { name: 'Focused Shot', cooldown: 10, desc: 'After a 1.2s aim, fires a piercing railgun shot for 110 damage.' },
    brain: 'artillery',
    visual: { shape: 'humanoid', size: 0.95, weapon: 'rifle', head: 'scope' },
    color: '#f5a742', accent: '#9c6418',
    desc: 'Extreme range marksman. Deletes priority targets; helpless up close.',
    upgrades: [U('sniper_pierceup'), U('sniper_deadeye')]
  },
  engineer: {
    id: 'engineer', name: 'Engineer', category: 'specialist', faction: 'scrapworks',
    cost: 130, hp: 90, speed: 92, radius: 10, armor: 0,
    attack: { range: 150, damage: 10, cooldown: 1.0, type: 'projectile', projectile: 'bolt', windup: 0.2, knockback: 20 },
    ability: { name: 'Deploy Turret', cooldown: 14, desc: 'Builds an auto-turret (70 HP) that shoots nearby enemies for 12/0.8s.' },
    brain: 'engineer',
    visual: { shape: 'humanoid', size: 0.95, weapon: 'wrench', head: 'goggles' },
    color: '#f0a35e', accent: '#8a5a22',
    desc: 'Turns territory into firepower. Turrets keep shooting after the engineer moves on.',
    upgrades: [U('engineer_upgradeturret'), U('engineer_nest')]
  },
  disruptor: {
    id: 'disruptor', name: 'Disruptor', category: 'specialist', faction: 'prism',
    cost: 120, hp: 85, speed: 96, radius: 10, armor: 0,
    attack: { range: 190, damage: 12, cooldown: 1.15, type: 'projectile', projectile: 'zap', windup: 0.22, knockback: 15 },
    ability: { name: 'Static Leash', cooldown: 8, desc: 'Leashes the nearest enemy ability-user: stunned 1.2s, then slowed.' },
    brain: 'disruptor',
    visual: { shape: 'robed', size: 1.0, weapon: 'prongs', head: 'spikes' },
    color: '#e57bd0', accent: '#8a2f74',
    desc: 'Shutdown specialist. Freezes Medics, Commanders and Casters mid-cast.',
    upgrades: [U('disruptor_blackout'), U('disruptor_feedback')]
  },
  commander: {
    id: 'commander', name: 'Commander', category: 'commander', faction: 'vanguard',
    cost: 160, hp: 115, speed: 90, radius: 11, armor: 0.05,
    attack: { range: 36, damage: 15, cooldown: 0.95, type: 'melee', windup: 0.2, knockback: 60 },
    ability: { name: 'Battle Cry', cooldown: 12, desc: 'Allies within 200px gain +15% damage and +20% speed for 5s.' },
    brain: 'commander',
    visual: { shape: 'humanoid', size: 1.1, weapon: 'banner', head: 'plume' },
    color: '#f2e27a', accent: '#9c8a2a',
    desc: 'Force multiplier. Stays behind the line and makes everyone hit harder.',
    upgrades: [U('commander_phoenix'), U('commander_warlord')]
  },
  trickster: {
    id: 'trickster', name: 'Trickster', category: 'agile', faction: 'prism',
    cost: 100, hp: 78, speed: 140, radius: 9, armor: 0,
    attack: { range: 28, damage: 11, cooldown: 0.6, type: 'melee', windup: 0.1, knockback: 30 },
    ability: { name: 'Blink & Decoy', cooldown: 7, desc: 'Blinks behind the enemy backline and leaves a decoy enemies chase.' },
    brain: 'trickster',
    visual: { shape: 'humanoid', size: 0.9, weapon: 'fans', head: 'mask' },
    color: '#e57bd0', accent: '#7a2f6a',
    desc: 'Chaos agent. Splits enemy attention and assassinates stragglers.',
    upgrades: [U('trickster_mirage'), U('trickster_shadow')]
  },
  artificer: {
    id: 'artificer', name: 'Artificer', category: 'support', faction: 'wildgrove',
    cost: 115, hp: 95, speed: 90, radius: 10, armor: 0,
    attack: { range: 140, damage: 9, cooldown: 1.2, type: 'projectile', projectile: 'seed', windup: 0.22, knockback: 15 },
    ability: { name: 'Growth Totem', cooldown: 13, desc: 'Plants a totem regenerating nearby allies 9 HP/s for 12s.' },
    brain: 'artificer',
    visual: { shape: 'robed', size: 1.0, weapon: 'lantern', head: 'leaf' },
    color: '#a5e07a', accent: '#4a7a2f',
    desc: 'Zone control support. Totems anchor defensive positions.',
    upgrades: [U('artificer_grove'), U('artificer_twin')]
  },
  phoenix: {
    id: 'phoenix', name: 'Phoenix', category: 'specialist', faction: 'prism',
    cost: 160, hp: 115, speed: 105, radius: 10, armor: 0,
    attack: { range: 170, damage: 13, cooldown: 1.1, type: 'projectile', projectile: 'bolt', windup: 0.22, knockback: 15 },
    ability: { name: 'Immolate', cooldown: 9, desc: 'Erupts in flame: 22 damage to nearby enemies and a burst of speed.' },
    rebirth: { hpFrac: 0.35, novaDamage: 20, novaRadius: 120, novaKnockback: 200 },
    brain: 'caster',
    visual: { shape: 'robed', size: 1.0, weapon: 'orb', head: 'wreath' },
    color: '#ff9d5c', accent: '#a83a1a',
    desc: 'A blazing spirit that dies twice. The first death detonates in a nova and it rises again.',
    upgrades: [U('phoenix_ember'), U('phoenix_solar')]
  },
  reaper: {
    id: 'reaper', name: 'Reaper', category: 'agile', faction: 'wildgrove',
    cost: 150, hp: 165, speed: 125, radius: 9, armor: 0.05,
    attack: { range: 38, damage: 16, cooldown: 0.7, type: 'melee', windup: 0.14, knockback: 40, lifesteal: 0.6 },
    ability: { name: 'Soul Siphon', cooldown: 8, desc: 'Tears the life from the most wounded nearby enemy: 40 damage, healing itself for 80%.' },
    brain: 'skirmisher',
    visual: { shape: 'robed', size: 1.05, weapon: 'scythe', head: 'hood' },
    color: '#9de07a', accent: '#2a5a3a',
    desc: 'Every wound it deals feeds it. Force it to burn targets down fast or it never stops coming.',
    upgrades: [U('reaper_bloodmoon'), U('reaper_deathwing')]
  },
  colossus: {
    id: 'colossus', name: 'Colossus', category: 'heavy', faction: 'scrapworks',
    cost: 400, hp: 950, speed: 55, radius: 20, armor: 0.25,
    attack: { range: 52, damage: 42, cooldown: 1.8, type: 'melee', windup: 0.4, knockback: 240 },
    ability: { name: 'Sweep', cooldown: 7, desc: 'A massive arc: 55 damage and huge knockback to everything within 130px.' },
    brain: 'titan',
    visual: { shape: 'mech', size: 2.0, weapon: 'fists', head: 'core' },
    color: '#f5a742', accent: '#5a4423',
    desc: 'A walking siege engine. Nearly unkillable alone — countered by focus fire and kiting.',
    upgrades: [U('colossus_meteor'), U('colossus_titan')]
  }
};

export const UNIT_LIST = Object.values(UNITS);

export function getUnit(id) { return UNITS[id]; }

// Resolve a def + optional upgrade id into a concrete def clone.
export function resolveDef(unitId, upgradeId) {
  const base = UNITS[unitId];
  if (!base) throw new Error('Unknown unit: ' + unitId);
  const d = JSON.parse(JSON.stringify(base));
  const up = upgradeId && UPGRADES[upgradeId];
  if (up) {
    d.upgrade = up.id;
    d.upgradeName = up.name;
    if (up.apply) up.apply(d);
  }
  const fac = d.factionBonus || {};
  return d;
}

// Faction bonuses applied at spawn time inside the sim (mutating live def).
