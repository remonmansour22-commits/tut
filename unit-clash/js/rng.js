// Deterministic seeded RNG. All simulation randomness flows through here so
// battles with the same seed and configuration replay identically.

export function hashSeed(str) {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

export function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export class RNG {
  constructor(seed) {
    this.seedFn = typeof seed === 'string' ? mulberry32(hashSeed(seed)) : mulberry32(seed >>> 0);
    this.seed = seed;
  }
  next() { return this.seedFn(); }
  range(a, b) { return a + this.next() * (b - a); }
  int(a, b) { return Math.floor(this.range(a, b + 1)); }
  pick(arr) { return arr[Math.floor(this.next() * arr.length)]; }
  chance(p) { return this.next() < p; }
  // Approximate normal distribution via central limit, clamped to +/- 2 sigma
  gauss(mean, sigma) {
    const s = (this.next() + this.next() + this.next() + this.next() + this.next() + this.next()) / 6;
    return mean + (s - 0.5) * 4 * sigma;
  }
  angle() { return this.next() * Math.PI * 2; }
}
