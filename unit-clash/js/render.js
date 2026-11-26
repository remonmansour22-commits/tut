// ============================================================
// RENDERER — canvas 2D presentation. Consumes sim events and
// produces particles, floating text, shake. Never mutates sim state.
// ============================================================

import { hashSeed, RNG } from './rng.js';
import { ARENAS } from './arenas.js';
import { dist } from './ai.js';

const TEAM_COLORS = { A: '#4aa3ff', B: '#ff5a5a' };
const TEAM_DIM = { A: 'rgba(74,163,255,0.10)', B: 'rgba(255,90,90,0.10)' };

export class Renderer {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.cam = { x: 800, y: 450, zoom: 1 };
    this.targetCam = { x: 800, y: 450, zoom: 1 };
    this.follow = null; // unit to follow
    this.particles = [];
    this.floaters = [];
    this.shake = 0;
    this.arena = null;
    this.props = [];
    this.time = 0;
    this.flash = 0;
  }

  setArena(arenaId) {
    this.arena = ARENAS[arenaId] || ARENAS.grassland;
    const rng = new RNG(hashSeed(arenaId));
    this.props = [];
    const n = 10 + Math.floor(rng.next() * 8);
    for (let i = 0; i < n; i++) {
      this.props.push({
        x: rng.range(60, 1540), y: rng.range(70, 830),
        r: rng.range(6, 22), kind: rng.pick(['rock', 'bush', 'debris', 'crystal']),
        tone: rng.next()
      });
    }
  }

  worldToScreen(x, y) {
    return {
      x: (x - this.cam.x) * this.cam.zoom + this.canvas.width / 2,
      y: (y - this.cam.y) * this.cam.zoom + this.canvas.height / 2
    };
  }

  screenToWorld(sx, sy) {
    return {
      x: (sx - this.canvas.width / 2) / this.cam.zoom + this.cam.x,
      y: (sy - this.canvas.height / 2) / this.cam.zoom + this.cam.y
    };
  }

  overview(sim) {
    const w = this.canvas.width, h = this.canvas.height;
    const zoom = Math.min(w / (sim ? sim.W : 1600), h / (sim ? sim.H : 900)) * 0.98;
    this.targetCam = { x: 800, y: 450, zoom };
    this.follow = null;
  }

  addShake(p) { this.shake = Math.min(1.5, this.shake + p); }

  consumeEvents(events) {
    for (const ev of events) {
      switch (ev.type) {
        case 'hit':
          this.float(ev.crit ? `${ev.dmg}!` : `${ev.dmg}`, ev.x, ev.y, ev.crit ? '#ffd24a' : '#ffffff', ev.crit ? 17 : 12);
          this.burst(ev.x, ev.y, ev.crit ? 10 : 5, ev.crit ? '#ffd24a' : '#ffdf9a', 130);
          if (ev.crit) this.addShake(0.25);
          break;
        case 'shot':
          this.burst(ev.x, ev.y, 3, ev.color, 60);
          break;
        case 'death':
          this.burst(ev.x, ev.y, ev.big ? 34 : 16, ev.team === 'A' ? '#7db8ff' : '#ff9c8a', ev.big ? 240 : 170);
          this.ring(ev.x, ev.y, ev.big ? 60 : 34, ev.team === 'A' ? '#4aa3ff' : '#ff5a5a');
          if (ev.big) { this.addShake(0.9); this.flash = 0.35; }
          else this.addShake(0.15);
          break;
        case 'aoe':
          this.ring(ev.x, ev.y, ev.r, ev.color);
          break;
        case 'ability':
          this.float(ev.name, ev.x, ev.y - 26, ev.color, 12, 1.1);
          this.ring(ev.x, ev.y, 30, ev.color);
          break;
        case 'heal':
          if (ev.amount) this.float(`+${ev.amount}`, ev.x, ev.y, '#8fce6f', 12);
          this.burst(ev.x, ev.y, 4, '#8fce6f', 70);
          break;
        case 'shield': this.ring(ev.x, ev.y, 20, ev.color); break;
        case 'buff': this.float('▲', ev.x, ev.y - 14, ev.color, 12); break;
        case 'bounce': this.burst(ev.x, ev.y, 6, ev.color, 120); break;
        case 'blink': this.ring(ev.x, ev.y, 26, ev.color); this.burst(ev.x, ev.y, 12, ev.color, 160); break;
        case 'deviceDown': this.burst(ev.x, ev.y, 8, ev.color, 120); break;
        case 'decoyPop': this.burst(ev.x, ev.y, 10, '#e57bd0', 130); break;
        case 'rebirth':
          this.ring(ev.x, ev.y, ev.r || 120, ev.color || '#ff9d5c');
          this.burst(ev.x, ev.y, 22, ev.color || '#ff9d5c', 260);
          this.float('REBIRTH!', ev.x, ev.y - 24, ev.color || '#ff9d5c', 15);
          break;
        case 'spawn': this.ring(ev.x, ev.y, 24, TEAM_COLORS[ev.team]); break;
        case 'victory':
          this.addShake(0.5);
          this.flash = 0.5;
          break;
        case 'shake': this.addShake(ev.power); break;
      }
    }
  }

  burst(x, y, n, color, speed) {
    if (this.particles.length > 900) return;
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2;
      const s = speed * (0.4 + Math.random() * 0.8);
      this.particles.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 0.5 + Math.random() * 0.4, maxLife: 0.9, color, r: 1.5 + Math.random() * 2.5 });
    }
  }

  ring(x, y, r, color) {
    this.particles.push({ ring: true, x, y, r: 6, maxR: r, life: 0.4, maxLife: 0.4, color });
  }

  float(text, x, y, color, size, life = 0.85) {
    if (this.floaters.length > 120) this.floaters.shift();
    this.floaters.push({ text, x, y, color, size, life, maxLife: life, vy: -42 });
  }

  updateFx(dt) {
    this.time += dt;
    this.shake = Math.max(0, this.shake - dt * 2.2);
    this.flash = Math.max(0, this.flash - dt * 2);
    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];
      p.life -= dt;
      if (p.life <= 0) { this.particles.splice(i, 1); continue; }
      if (!p.ring) {
        p.x += p.vx * dt; p.y += p.vy * dt;
        p.vx *= 0.92; p.vy *= 0.92;
      } else {
        p.r += (p.maxR - p.r) * Math.min(1, dt * 12);
      }
    }
    for (let i = this.floaters.length - 1; i >= 0; i--) {
      const f = this.floaters[i];
      f.life -= dt; f.y += f.vy * dt; f.vy *= 0.94;
      if (f.life <= 0) this.floaters.splice(i, 1);
    }
    // camera easing / follow
    if (this.follow && this.follow.alive) {
      this.targetCam.x = this.follow.x; this.targetCam.y = this.follow.y;
      this.targetCam.zoom = Math.max(this.targetCam.zoom, 1.1);
    }
    const k = Math.min(1, dt * 5);
    this.cam.x += (this.targetCam.x - this.cam.x) * k;
    this.cam.y += (this.targetCam.y - this.cam.y) * k;
    this.cam.zoom += (this.targetCam.zoom - this.cam.zoom) * k;
  }

  render(sim, state = {}) {
    const ctx = this.ctx;
    const cw = this.canvas.width, ch = this.canvas.height;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, cw, ch);

    const sh = this.shake;
    const ox = sh ? (Math.random() - 0.5) * 14 * sh : 0;
    const oy = sh ? (Math.random() - 0.5) * 14 * sh : 0;

    // sky
    const grad = ctx.createLinearGradient(0, 0, 0, ch);
    grad.addColorStop(0, this.arena.sky[0]);
    grad.addColorStop(1, this.arena.sky[1]);
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, cw, ch);

    ctx.save();
    ctx.translate(cw / 2 + ox, ch / 2 + oy);
    ctx.scale(this.cam.zoom, this.cam.zoom);
    ctx.translate(-this.cam.x, -this.cam.y);

    this.drawGround(ctx, sim);

    // team half tints (setup mode)
    if (state.phase === 'setup' && sim) {
      ctx.fillStyle = TEAM_DIM.A;
      ctx.fillRect(0, 0, sim.W / 2, sim.H);
      ctx.fillStyle = TEAM_DIM.B;
      ctx.fillRect(sim.W / 2, 0, sim.W / 2, sim.H);
      ctx.strokeStyle = 'rgba(255,255,255,0.25)';
      ctx.setLineDash([14, 10]);
      ctx.beginPath(); ctx.moveTo(sim.W / 2, 0); ctx.lineTo(sim.W / 2, sim.H); ctx.stroke();
      ctx.setLineDash([]);
    }

    // devices
    if (sim) for (const d of sim.devices) this.drawDevice(ctx, d);

    // units (sorted by y for depth)
    if (sim) {
      const sorted = sim.units.slice().sort((a, b) => a.y - b.y);
      for (const u of sorted) {
        if (u.alive) this.drawUnit(ctx, u, state);
        else if (u.deathT < 1.4) this.drawDeath(ctx, u);
      }
    }

    // projectiles
    if (sim) for (const p of sim.projectiles) this.drawProjectile(ctx, p);

    // particles
    for (const p of this.particles) {
      const a = Math.max(0, p.life / p.maxLife);
      if (p.ring) {
        ctx.strokeStyle = p.color; ctx.globalAlpha = a * 0.8; ctx.lineWidth = 3;
        ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2); ctx.stroke();
      } else {
        ctx.fillStyle = p.color; ctx.globalAlpha = a;
        ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2); ctx.fill();
      }
    }
    ctx.globalAlpha = 1;

    // floating text
    for (const f of this.floaters) {
      const a = Math.max(0, f.life / f.maxLife);
      ctx.globalAlpha = a;
      ctx.font = `bold ${f.size}px "Segoe UI", sans-serif`;
      ctx.textAlign = 'center';
      ctx.strokeStyle = 'rgba(0,0,0,0.6)'; ctx.lineWidth = 3;
      ctx.strokeText(f.text, f.x, f.y);
      ctx.fillStyle = f.color;
      ctx.fillText(f.text, f.x, f.y);
    }
    ctx.globalAlpha = 1;

    // selection + placement ghost
    if (state.selected && state.selected.alive) {
      const s = state.selected;
      ctx.strokeStyle = '#ffffff'; ctx.lineWidth = 2;
      ctx.setLineDash([5, 5]);
      ctx.beginPath(); ctx.arc(s.x, s.y, s.def.radius + 8, 0, Math.PI * 2); ctx.stroke();
      ctx.setLineDash([]);
      if (s.def.attack && s.def.attack.range > 40) {
        ctx.strokeStyle = 'rgba(255,255,255,0.15)';
        ctx.beginPath(); ctx.arc(s.x, s.y, s.def.attack.range, 0, Math.PI * 2); ctx.stroke();
      }
    }
    if (state.ghost) {
      const g = state.ghost;
      const def = g.def;
      ctx.globalAlpha = 0.6;
      this.drawUnitBody(ctx, g.x, g.y, def, 1, def.color, def.accent, 0, g.team);
      ctx.globalAlpha = 1;
      ctx.strokeStyle = TEAM_COLORS[g.team];
      ctx.beginPath(); ctx.arc(g.x, g.y, def.radius + 4, 0, Math.PI * 2); ctx.stroke();
      if (def.attack && def.attack.range > 40) {
        ctx.strokeStyle = 'rgba(255,255,255,0.18)';
        ctx.beginPath(); ctx.arc(g.x, g.y, def.attack.range, 0, Math.PI * 2); ctx.stroke();
      }
    }

    ctx.restore();

    if (this.flash > 0) {
      ctx.fillStyle = `rgba(255,255,255,${this.flash * 0.35})`;
      ctx.fillRect(0, 0, cw, ch);
    }
  }

  drawGround(ctx, sim) {
    const W = sim ? sim.W : 1600, H = sim ? sim.H : 900;
    const a = this.arena;
    ctx.fillStyle = a.ground;
    ctx.fillRect(0, 0, W, H);
    // subtle grid
    ctx.strokeStyle = a.line; ctx.globalAlpha = 0.12; ctx.lineWidth = 1;
    for (let x = 0; x <= W; x += 100) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, H); ctx.stroke(); }
    for (let y = 0; y <= H; y += 100) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke(); }
    ctx.globalAlpha = 1;
    // props
    for (const p of this.props) {
      ctx.globalAlpha = 0.5;
      ctx.fillStyle = a.groundAccent;
      if (p.kind === 'rock') { ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2); ctx.fill(); }
      else if (p.kind === 'bush') {
        ctx.beginPath(); ctx.arc(p.x, p.y, p.r * 0.8, 0, Math.PI * 2);
        ctx.arc(p.x + p.r * 0.6, p.y + 2, p.r * 0.6, 0, Math.PI * 2);
        ctx.arc(p.x - p.r * 0.6, p.y + 2, p.r * 0.6, 0, Math.PI * 2); ctx.fill();
      } else {
        ctx.fillRect(p.x - p.r / 2, p.y - p.r / 2, p.r, p.r * 0.6);
      }
    }
    ctx.globalAlpha = 1;
    // border
    ctx.strokeStyle = a.line; ctx.lineWidth = 4;
    ctx.strokeRect(2, 2, W - 4, H - 4);
  }

  drawDevice(ctx, d) {
    const pulse = 1 + Math.sin(this.time * 5) * 0.06;
    if (d.kind === 'turret') {
      ctx.fillStyle = '#5a4423';
      ctx.beginPath(); ctx.arc(d.x, d.y, 9, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = d.def.color;
      ctx.fillRect(d.x - 3, d.y - 14, 6, 10);
      ctx.strokeStyle = 'rgba(240,163,94,0.5)';
      ctx.beginPath(); ctx.arc(d.x, d.y, 230, 0, Math.PI * 2); ctx.stroke();
    } else if (d.kind === 'totem') {
      ctx.fillStyle = d.def.color;
      ctx.beginPath();
      ctx.moveTo(d.x, d.y - 20 * pulse); ctx.lineTo(d.x + 12, d.y + 10);
      ctx.lineTo(d.x - 12, d.y + 10); ctx.closePath(); ctx.fill();
      ctx.strokeStyle = 'rgba(165,224,122,0.35)';
      ctx.beginPath(); ctx.arc(d.x, d.y, d.radius, 0, Math.PI * 2); ctx.stroke();
      if (d.speedAura) {
        ctx.strokeStyle = 'rgba(165,224,122,0.18)';
        ctx.beginPath(); ctx.arc(d.x, d.y, d.radius * 1.3, 0, Math.PI * 2); ctx.stroke();
      }
    }
    // device hp
    if (d.hp < d.maxHp) {
      ctx.fillStyle = 'rgba(0,0,0,0.5)';
      ctx.fillRect(d.x - 12, d.y - 26, 24, 4);
      ctx.fillStyle = '#8fce6f';
      ctx.fillRect(d.x - 12, d.y - 26, 24 * (d.hp / d.maxHp), 4);
    }
  }

  drawUnit(ctx, u, state) {
    const def = u.def;
    // team ring on ground
    ctx.fillStyle = u.team === 'A' ? 'rgba(74,163,255,0.18)' : 'rgba(255,90,90,0.18)';
    ctx.beginPath(); ctx.ellipse(u.x, u.y + def.radius * 0.8, def.radius * 1.1, def.radius * 0.45, 0, 0, Math.PI * 2); ctx.fill();

    const bob = Math.sin(u.walkPhase) * 2;
    const lunge = u.attackAnim * (u.facing * 5);
    this.drawUnitBody(ctx, u.x + lunge, u.y + bob, def, u.facing, def.color, def.accent, u.hitFlash, u.team);

    // shield bubble
    if (u.shield > 0) {
      ctx.strokeStyle = 'rgba(143,211,255,0.8)'; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(u.x, u.y, def.radius + 7, 0, Math.PI * 2); ctx.stroke();
      ctx.fillStyle = 'rgba(143,211,255,0.10)'; ctx.fill();
    }
    if (u.hasStatus('stun')) {
      ctx.fillStyle = '#ffe066';
      ctx.font = '10px sans-serif'; ctx.textAlign = 'center';
      ctx.fillText('✦', u.x, u.y - def.radius - 12);
    }

    // health bar (only when damaged or selected)
    if (u.hp < u.maxHp || state.selected === u || state.alwaysBars) {
      const w = Math.max(22, def.radius * 2.4);
      const y = u.y - def.radius - 10;
      ctx.fillStyle = 'rgba(0,0,0,0.55)';
      ctx.fillRect(u.x - w / 2 - 1, y - 1, w + 2, 5.5);
      const frac = Math.max(0, u.hp / u.maxHp);
      ctx.fillStyle = frac > 0.5 ? '#7ddb6f' : frac > 0.25 ? '#e8c46b' : '#e05f5f';
      ctx.fillRect(u.x - w / 2, y, w * frac, 3.5);
      if (u.shield > 0) {
        ctx.fillStyle = '#8fd3ff';
        ctx.fillRect(u.x - w / 2, y - 3, w * Math.min(1, u.shield / u.maxHp), 2);
      }
    }
    // status pips
    const statuses = u.statuses.filter(s => ['slow', 'haste', 'buff', 'silence', 'regen'].includes(s.type));
    if (statuses.length) {
      const colors = { slow: '#9ab0c8', haste: '#7ee0a3', buff: '#f2e27a', silence: '#e57bd0', regen: '#8fce6f' };
      statuses.forEach((s, i) => {
        ctx.fillStyle = colors[s.type];
        ctx.beginPath(); ctx.arc(u.x - (statuses.length - 1) * 4 + i * 8, u.y - def.radius - 16, 2.6, 0, Math.PI * 2); ctx.fill();
      });
    }
  }

  drawUnitBody(ctx, x, y, def, facing, color, accent, flash, team) {
    const s = (def.visual && def.visual.size) || 1;
    const r = (def.radius || 10) * s;
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(facing, 1);
    const shape = def.visual ? def.visual.shape : 'humanoid';
    ctx.lineJoin = 'round';

    if (shape === 'decoy') ctx.globalAlpha = 0.55;

    // legs
    ctx.strokeStyle = accent; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.moveTo(-r * 0.35, r * 0.4); ctx.lineTo(-r * 0.35, r * 0.95); ctx.moveTo(r * 0.35, r * 0.4); ctx.lineTo(r * 0.35, r * 0.95); ctx.stroke();

    // body
    ctx.fillStyle = color;
    ctx.strokeStyle = accent; ctx.lineWidth = 2;
    if (shape === 'bulky' || shape === 'mech') {
      const w = shape === 'mech' ? r * 1.5 : r * 1.25;
      roundRect(ctx, -w * 0.55, -r * 0.6, w, r * 1.1, r * 0.25);
      if (shape === 'mech') {
        ctx.fillStyle = accent;
        ctx.beginPath(); ctx.arc(r * 0.15, -r * 0.05, r * 0.22, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = color;
        roundRect(ctx, -w * 0.75, -r * 0.5, w * 0.25, r * 0.7, 3);
      }
    } else if (shape === 'robed') {
      ctx.beginPath();
      ctx.moveTo(0, -r * 0.7);
      ctx.lineTo(r * 0.75, r * 0.95);
      ctx.lineTo(-r * 0.75, r * 0.95);
      ctx.closePath(); ctx.fill(); ctx.stroke();
    } else {
      roundRect(ctx, -r * 0.55, -r * 0.55, r * 1.1, r * 1.05, r * 0.3);
    }

    // head
    const hy = shape === 'mech' ? -r * 0.95 : -r * 0.85;
    ctx.fillStyle = '#f5e9d8';
    ctx.strokeStyle = accent;
    ctx.beginPath(); ctx.arc(r * 0.05, hy, r * 0.42, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
    // eye
    ctx.fillStyle = '#2a2a35';
    ctx.beginPath(); ctx.arc(r * 0.22, hy, r * 0.08, 0, Math.PI * 2); ctx.fill();

    // headgear
    const head = def.visual && def.visual.head;
    ctx.fillStyle = accent;
    if (head === 'crest') roundRect(ctx, -r * 0.4, hy - r * 0.62, r * 0.9, r * 0.2, 2);
    else if (head === 'helm') { ctx.beginPath(); ctx.arc(r * 0.05, hy - r * 0.1, r * 0.48, Math.PI, 0); ctx.fill(); }
    else if (head === 'hood') { ctx.beginPath(); ctx.arc(r * 0.05, hy - r * 0.05, r * 0.5, Math.PI * 0.9, Math.PI * 2.1); ctx.fill(); }
    else if (head === 'plume') { ctx.fillRect(-r * 0.05, hy - r * 0.85, r * 0.16, r * 0.45); }
    else if (head === 'antenna') { ctx.fillRect(r * 0.0, hy - r * 0.75, r * 0.08, r * 0.4); }
    else if (head === 'visor') roundRect(ctx, -r * 0.1, hy - r * 0.15, r * 0.6, r * 0.18, 2);
    else if (head === 'scope') roundRect(ctx, r * 0.15, hy - r * 0.12, r * 0.5, r * 0.16, 2);
    else if (head === 'goggles') { ctx.beginPath(); ctx.arc(r * 0.25, hy, r * 0.16, 0, Math.PI * 2); ctx.stroke(); }
    else if (head === 'spikes') { ctx.beginPath(); ctx.moveTo(-r * 0.2, hy - r * 0.3); ctx.lineTo(r * 0.05, hy - r * 0.65); ctx.lineTo(r * 0.3, hy - r * 0.3); ctx.fill(); }
    else if (head === 'mask') roundRect(ctx, r * 0.05, hy - r * 0.5, r * 0.5, r * 0.14, 2);
    else if (head === 'leaf') { ctx.beginPath(); ctx.ellipse(-r * 0.15, hy - r * 0.5, r * 0.3, r * 0.14, -0.6, 0, Math.PI * 2); ctx.fill(); }
    else if (head === 'band') roundRect(ctx, -r * 0.35, hy - r * 0.45, r * 0.85, r * 0.14, 2);
    else if (head === 'core') { ctx.beginPath(); ctx.arc(r * 0.05, hy, r * 0.2, 0, Math.PI * 2); ctx.fill(); }
    else if (head === 'wreath') {
      ctx.strokeStyle = accent;
      ctx.beginPath(); ctx.arc(r * 0.05, hy - r * 0.15, r * 0.42, -0.4, Math.PI + 0.4); ctx.stroke();
      ctx.fillStyle = color;
      ctx.beginPath(); ctx.moveTo(r * 0.05, hy - r * 0.75); ctx.lineTo(r * 0.22, hy - r * 0.45); ctx.lineTo(-r * 0.12, hy - r * 0.45); ctx.fill();
    }

    // weapon
    const weapon = def.visual && def.visual.weapon;
    ctx.strokeStyle = accent; ctx.fillStyle = accent; ctx.lineWidth = 3;
    const wx = r * 0.6, wy = -r * 0.1;
    switch (weapon) {
      case 'dagger': ctx.beginPath(); ctx.moveTo(wx, wy); ctx.lineTo(wx + r * 0.5, wy - r * 0.25); ctx.stroke(); break;
      case 'axe':
        ctx.beginPath(); ctx.moveTo(wx, wy + r * 0.3); ctx.lineTo(wx, wy - r * 0.5); ctx.stroke();
        ctx.beginPath(); ctx.arc(wx + r * 0.1, wy - r * 0.4, r * 0.22, -1.2, 1.2); ctx.fill(); break;
      case 'shield':
        ctx.fillStyle = color;
        roundRect(ctx, wx - r * 0.15, wy - r * 0.45, r * 0.4, r * 0.9, r * 0.15);
        ctx.strokeStyle = accent;
        roundRect(ctx, wx - r * 0.15, wy - r * 0.45, r * 0.4, r * 0.9, r * 0.15); break;
      case 'staff':
        ctx.beginPath(); ctx.moveTo(wx, wy + r * 0.5); ctx.lineTo(wx, wy - r * 0.7); ctx.stroke();
        ctx.fillStyle = color;
        ctx.beginPath(); ctx.arc(wx, wy - r * 0.75, r * 0.14 + Math.sin(this.time * 4) * 0.8, 0, Math.PI * 2); ctx.fill(); break;
      case 'coil':
        ctx.beginPath(); ctx.arc(wx + r * 0.1, wy - r * 0.3, r * 0.2, 0, Math.PI * 1.5); ctx.stroke();
        ctx.fillStyle = color;
        ctx.beginPath(); ctx.arc(wx + r * 0.1, wy - r * 0.3, r * 0.09, 0, Math.PI * 2); ctx.fill(); break;
      case 'rifle':
        ctx.lineWidth = 4;
        ctx.beginPath(); ctx.moveTo(wx - r * 0.2, wy); ctx.lineTo(wx + r * 0.9, wy - r * 0.2); ctx.stroke(); break;
      case 'wrench':
        ctx.beginPath(); ctx.moveTo(wx, wy + r * 0.3); ctx.lineTo(wx, wy - r * 0.4); ctx.stroke();
        ctx.beginPath(); ctx.arc(wx, wy - r * 0.45, r * 0.12, 0, Math.PI * 2); ctx.stroke(); break;
      case 'prongs':
        ctx.beginPath();
        ctx.moveTo(wx, wy + r * 0.3); ctx.lineTo(wx - r * 0.1, wy - r * 0.5);
        ctx.moveTo(wx, wy + r * 0.3); ctx.lineTo(wx + r * 0.15, wy - r * 0.5); ctx.stroke(); break;
      case 'banner':
        ctx.beginPath(); ctx.moveTo(wx, wy + r * 0.5); ctx.lineTo(wx, wy - r * 1.0); ctx.stroke();
        ctx.fillStyle = color;
        ctx.beginPath(); ctx.moveTo(wx, wy - r * 1.0); ctx.lineTo(wx + r * 0.55, wy - r * 0.85); ctx.lineTo(wx, wy - r * 0.7); ctx.fill(); break;
      case 'fans':
        ctx.beginPath(); ctx.arc(wx, wy, r * 0.3, -2.2, -0.6); ctx.stroke(); break;
      case 'lantern':
        ctx.beginPath(); ctx.moveTo(wx, wy); ctx.lineTo(wx + r * 0.05, wy - r * 0.4); ctx.stroke();
        ctx.fillStyle = '#ffe9a8';
        ctx.beginPath(); ctx.arc(wx + r * 0.05, wy - r * 0.5, r * 0.12, 0, Math.PI * 2); ctx.fill(); break;
      case 'hammer':
        ctx.beginPath(); ctx.moveTo(wx, wy + r * 0.4); ctx.lineTo(wx, wy - r * 0.5); ctx.stroke();
        roundRect(ctx, wx - r * 0.05, wy - r * 0.7, r * 0.35, r * 0.3, 3); break;
      case 'fists':
        ctx.beginPath(); ctx.arc(wx, wy, r * 0.28, 0, Math.PI * 2); ctx.fill(); break;
      case 'orb': {
        ctx.beginPath(); ctx.moveTo(wx, wy + r * 0.3); ctx.lineTo(wx, wy - r * 0.4); ctx.stroke();
        const glow = 0.6 + Math.sin(this.time * 5) * 0.4;
        ctx.globalAlpha = glow;
        ctx.fillStyle = color;
        ctx.beginPath(); ctx.arc(wx, wy - r * 0.5, r * 0.24, 0, Math.PI * 2); ctx.fill();
        ctx.globalAlpha = 1; break;
      }
      case 'scythe': {
        ctx.lineWidth = 3;
        ctx.beginPath(); ctx.moveTo(wx, wy + r * 0.45); ctx.lineTo(wx, wy - r * 0.7); ctx.stroke();
        ctx.beginPath(); ctx.arc(wx + r * 0.12, wy - r * 0.62, r * 0.34, Math.PI * 1.15, Math.PI * 1.85); ctx.stroke(); break;
      }
      default: break;
    }

    if (flash > 0) {
      ctx.globalAlpha = flash * 0.7;
      ctx.fillStyle = '#ffffff';
      ctx.beginPath(); ctx.arc(0, 0, r * 1.15, 0, Math.PI * 2); ctx.fill();
    }
    ctx.restore();
  }

  drawDeath(ctx, u) {
    const t = Math.min(1, u.deathT / 1.4);
    ctx.globalAlpha = (1 - t) * 0.8;
    ctx.save();
    ctx.translate(u.x, u.y + t * 6);
    ctx.rotate((u.facing > 0 ? 1 : -1) * t * 1.4);
    ctx.fillStyle = u.def.color;
    ctx.beginPath(); ctx.arc(0, 0, u.def.radius * 0.8, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
    ctx.globalAlpha = 1;
  }

  drawProjectile(ctx, p) {
    if (p.trail.length >= 4) {
      ctx.strokeStyle = p.color;
      ctx.globalAlpha = 0.4;
      ctx.lineWidth = p.radius * 1.2;
      ctx.lineCap = 'round';
      ctx.beginPath();
      ctx.moveTo(p.trail[0], p.trail[1]);
      for (let i = 2; i < p.trail.length; i += 2) ctx.lineTo(p.trail[i], p.trail[i + 1]);
      ctx.stroke();
      ctx.globalAlpha = 1;
    }
    ctx.fillStyle = p.color;
    ctx.shadowColor = p.color;
    ctx.shadowBlur = 8;
    ctx.beginPath(); ctx.arc(p.x, p.y, p.radius, 0, Math.PI * 2); ctx.fill();
    ctx.shadowBlur = 0;
    if (p.type === 'rail') {
      ctx.strokeStyle = p.color;
      ctx.lineWidth = 2;
      const l = Math.hypot(p.vx, p.vy) || 1;
      ctx.beginPath();
      ctx.moveTo(p.x - p.vx / l * 26, p.y - p.vy / l * 26);
      ctx.lineTo(p.x, p.y);
      ctx.stroke();
    }
  }
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
  ctx.fill();
}
