// Tiny synthesized SFX via WebAudio — no audio assets required.
export class AudioController {
  constructor() {
    this.ctx = null;
    this.muted = false;
    this.master = null;
    this.lastPlay = {};
  }
  ensure() {
    if (this.ctx) return true;
    try {
      this.ctx = new (window.AudioContext || window.webkitAudioContext)();
      this.master = this.ctx.createGain();
      this.master.gain.value = 0.16;
      this.master.connect(this.ctx.destination);
      return true;
    } catch { return false; }
  }
  throttle(key, ms) {
    const now = performance.now();
    if (this.lastPlay[key] && now - this.lastPlay[key] < ms) return false;
    this.lastPlay[key] = now;
    return true;
  }
  tone(freq, dur, type = 'sine', vol = 1, slide = 0) {
    if (this.muted || !this.ensure()) return;
    const t = this.ctx.currentTime;
    const o = this.ctx.createOscillator();
    const g = this.ctx.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(30, freq + slide), t + dur);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(g); g.connect(this.master);
    o.start(t); o.stop(t + dur + 0.02);
  }
  noise(dur, vol = 0.5, filterFreq = 1200) {
    if (this.muted || !this.ensure()) return;
    const t = this.ctx.currentTime;
    const len = Math.max(1, Math.floor(this.ctx.sampleRate * dur));
    const buf = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
    const data = buf.getChannelData(0);
    for (let i = 0; i < len; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / len);
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    const f = this.ctx.createBiquadFilter();
    f.type = 'lowpass'; f.frequency.value = filterFreq;
    const g = this.ctx.createGain();
    g.gain.value = vol;
    src.connect(f); f.connect(g); g.connect(this.master);
    src.start(t);
  }
  place() { this.tone(520, 0.08, 'triangle', 0.6); }
  remove() { this.tone(300, 0.1, 'triangle', 0.5, -100); }
  start() { this.tone(392, 0.12, 'square', 0.5); setTimeout(() => this.tone(523, 0.12, 'square', 0.5), 110); setTimeout(() => this.tone(659, 0.2, 'square', 0.6), 220); }
  hit() { if (this.throttle('hit', 45)) this.noise(0.06, 0.35, 900); }
  crit() { if (this.throttle('crit', 60)) { this.noise(0.1, 0.6, 2000); this.tone(880, 0.08, 'square', 0.4, 200); } }
  shot() { if (this.throttle('shot', 50)) this.tone(660, 0.06, 'sawtooth', 0.25, -300); }
  heal() { if (this.throttle('heal', 120)) this.tone(700, 0.15, 'sine', 0.3, 200); }
  ability() { if (this.throttle('ability', 80)) this.tone(240, 0.25, 'sawtooth', 0.4, 300); }
  death() { if (this.throttle('death', 80)) { this.noise(0.18, 0.5, 500); this.tone(180, 0.2, 'triangle', 0.4, -80); } }
  victory() { [523, 659, 784, 1047].forEach((f, i) => setTimeout(() => this.tone(f, 0.22, 'triangle', 0.6), i * 130)); }
  defeat() { [392, 330, 262].forEach((f, i) => setTimeout(() => this.tone(f, 0.3, 'triangle', 0.5), i * 180)); }
}
