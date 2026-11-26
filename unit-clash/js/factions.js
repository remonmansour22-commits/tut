// Faction identities. Bonuses are small, per-unit, and push playstyle not power.
export const FACTIONS = {
  scrapworks: {
    id: 'scrapworks', name: 'Scrapworks', color: '#f5a742',
    blurb: 'Inventors and tinkerers. Improvised machines that get better the longer they run.',
    bonusText: 'Devices last +50% longer; turrets fire faster.',
    apply(def) {
      def.deviceLifeMul = (def.deviceLifeMul || 1) * 1.5;
      def.deviceRateMul = (def.deviceRateMul || 1) * 1.25;
    }
  },
  vanguard: {
    id: 'vanguard', name: 'Vanguard', color: '#6fa8dc',
    blurb: 'Disciplined shield-line soldiers. Slow to break, faster when standing together.',
    bonusText: '+12% damage reduction while 2+ allies are within 120px.',
    apply(def) {
      def.formationArmor = (def.formationArmor || 0) + 0.08;
    }
  },
  wildgrove: {
    id: 'wildgrove', name: 'Wildgrove', color: '#8fce6f',
    blurb: 'Wardens of the grove. Growth, regeneration and thorny surprises.',
    bonusText: 'All healing this unit receives or gives is +20%.',
    apply(def) {
      def.healingMul = (def.healingMul || 1) * 1.2;
    }
  },
  prism: {
    id: 'prism', name: 'Prism Division', color: '#c77dff',
    blurb: 'Energy researchers bending light into weapons. Abilities come back quickly.',
    bonusText: 'Ability cooldowns recover 20% faster.',
    apply(def) {
      def.abilityRateMul = (def.abilityRateMul || 1) * 1.2;
    }
  }
};
