// Lightweight progression: XP, levels, unit mastery, achievements.
// Sandbox experimentation is never gated — progression only adds
// cosmetics, upgrade availability in challenge modes, and records.

import { SaveService } from './save.js';
import { UNIT_LIST } from './units.js';

export const LEVEL_XP = level => 100 + (level - 1) * 150;

export const ACHIEVEMENTS = [
  { id: 'first_blood', name: 'First Blood', desc: 'Win your first battle.' },
  { id: 'lab_rat', name: 'Lab Rat', desc: 'Run a Battle Lab experiment.' },
  { id: 'scientist', name: 'Field Scientist', desc: 'Run 10 experiment battles.' },
  { id: 'underdog', name: 'Underdog', desc: 'Win while out-spent by 200+ budget.' },
  { id: 'big_game', name: 'Big Game Hunter', desc: 'Win a battle against a Colossus.' },
  { id: 'allrounder', name: 'All-Rounder', desc: 'Win using all 7 unit categories.' },
  { id: 'survivor5', name: 'Wave Rider', desc: 'Reach wave 5 in Survival.' },
  { id: 'campaigner', name: 'Campaigner', desc: 'Complete the campaign.' },
  { id: 'collector', name: 'Field Tested', desc: 'Field every unit at least once.' }
];

export class ProgressionService {
  constructor() {
    this.profile = SaveService.getProfile();
  }
  save() { SaveService.setProfile(this.profile); }

  addXP(amount) {
    this.profile.xp += amount;
    let leveled = false;
    while (this.profile.xp >= LEVEL_XP(this.profile.level)) {
      this.profile.xp -= LEVEL_XP(this.profile.level);
      this.profile.level++;
      leveled = true;
    }
    this.save();
    return leveled;
  }

  recordUnitUse(unitIds) {
    for (const id of unitIds) {
      this.profile.mastery[id] = (this.profile.mastery[id] || 0) + 1;
    }
    this.save();
  }

  masteryOf(unitId) { return this.profile.mastery[unitId] || 0; }

  masteryTier(unitId) {
    const n = this.masteryOf(unitId);
    if (n >= 50) return { name: 'Veteran', tier: 3 };
    if (n >= 15) return { name: 'Seasoned', tier: 2 };
    if (n >= 5) return { name: 'Familiar', tier: 1 };
    return { name: 'New', tier: 0 };
  }

  has(id) { return this.profile.achievements.includes(id); }

  unlock(id) {
    if (this.has(id)) return null;
    this.profile.achievements.push(id);
    this.save();
    const a = ACHIEVEMENTS.find(x => x.id === id);
    return a;
  }

  fieldedUnits() { return new Set(Object.keys(this.profile.mastery)); }
  allUnitsFielded() {
    return UNIT_LIST.every(u => (this.profile.mastery[u.id] || 0) > 0);
  }

  // Upgrade availability: sandbox always allows; challenge modes require level.
  upgradesUnlockedFor(unitDef, mode) {
    if (mode === 'sandbox') return true;
    return unitDef.upgrades ? unitDef.upgrades.every(u => this.profile.level >= u.reqLevel) : true;
  }
}
