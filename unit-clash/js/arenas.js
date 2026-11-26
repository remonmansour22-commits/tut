// Arena definitions: pure data. The renderer interprets palette/props,
// the simulation reads modifiers.

export const ARENAS = {
  grassland: {
    id: 'grassland', name: 'Grassland', unlockLevel: 0,
    sky: ['#1b2a24', '#0f1713'], ground: '#2d4a33', groundAccent: '#3a5f41', line: '#4a7a55',
    blurb: 'Open field. No surprises — the purest test of armies.',
    modifiers: []
  },
  desert: {
    id: 'desert', name: 'Dust Basin', unlockLevel: 0,
    sky: ['#2b2313', '#171208'], ground: '#4a3b22', groundAccent: '#5c4a2b', line: '#7a6238',
    blurb: 'Shifting sands: slippery footing makes charges overshoot.',
    modifiers: ['slippery']
  },
  frozen: {
    id: 'frozen', name: 'Frozen Reach', unlockLevel: 0,
    sky: ['#16222e', '#0b1118'], ground: '#274356', groundAccent: '#33586f', line: '#4d7d99',
    blurb: 'A frozen lake. Very slippery; knockback slides much further.',
    modifiers: ['slippery', 'heavyKnockback']
  },
  industrial: {
    id: 'industrial', name: 'Industrial Yard', unlockLevel: 1,
    sky: ['#241d1d', '#120d0d'], ground: '#3a3438', groundAccent: '#4a4348', line: '#5f555c',
    blurb: 'Crosswinds between the warehouses push every projectile.',
    modifiers: ['wind']
  },
  rooftop: {
    id: 'rooftop', name: 'Rooftops', unlockLevel: 2,
    sky: ['#1d1830', '#0e0b18'], ground: '#33284a', groundAccent: '#41335e', line: '#5b4880',
    blurb: 'High altitude, thin air: everything gets knocked around. Low gravity.',
    modifiers: ['lowGravity']
  },
  training: {
    id: 'training', name: 'Training Grounds', unlockLevel: 0,
    sky: ['#1e2429', '#101418'], ground: '#2c343a', groundAccent: '#39424a', line: '#4e5b66',
    blurb: 'Neutral grounds for fair fights. No environmental modifiers.',
    modifiers: []
  }
};

// Modifier effects (read by simulation):
// slippery        -> lower friction/acceleration; units glide
// wind            -> constant sideways force on projectiles
// lowGravity      -> arc projectiles float, knockback travels ~40% further
// heavyKnockback  -> knockback travels further (ice slide)
export const MODIFIER_INFO = {
  slippery: { name: 'Slippery', desc: 'Units accelerate and brake slower.' },
  wind: { name: 'Crosswind', desc: 'Projectiles drift with the wind.' },
  lowGravity: { name: 'Low Gravity', desc: 'Arched shots float; knockback travels further.' },
  heavyKnockback: { name: 'Ice Slide', desc: 'Knockback carries units much further.' }
};
