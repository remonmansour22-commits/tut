// ============================================================
// UI CONTROLLER + GAME LOOP. Owns DOM, input, phases, modes,
// and delegates simulation to BattleSim and experiments to BattleLab.
// ============================================================

import { BattleSim, WORLD } from './sim.js';
import { Renderer } from './render.js';
import { AudioController } from './audio.js';
import { UNITS, UNIT_LIST, CATEGORIES, UPGRADES, resolveDef } from './units.js';
import { FACTIONS } from './factions.js';
import { ARENAS, MODIFIER_INFO } from './arenas.js';
import { generateInsights } from './stats.js';
import { SaveService } from './save.js';
import { ProgressionService, ACHIEVEMENTS } from './progression.js';
import { BattleLab, cloneConfig, unitCost, configCost, matrixScores } from './battlelab.js';
import { CAMPAIGN, dailyChallenge, randomArmy, layoutArmy, generateEnemyFor } from './modes.js';
import { RNG } from './rng.js';

const $ = id => document.getElementById(id);

export class GameController {
  constructor() {
    this.canvas = $('battlefield');
    this.renderer = new Renderer(this.canvas);
    this.audio = new AudioController();
    this.progression = new ProgressionService();
    this.lab = new BattleLab(() => this.renderLab());

    this.phase = 'setup'; // setup | battle | results
    this.mode = 'sandbox';
    this.campaignIndex = this.progression.profile.campaignProgress || 0;
    this.survival = { wave: 1, playerUnits: [] };

    this.config = this.blankConfig();
    this.selectedType = null;
    this.selectedEntry = null;
    this.selectedUnit = null;
    this.team = 'A';
    this.placingUpgrade = null;
    this.speed = 1;
    this.paused = false;
    this.following = false;
    this.hoverWorld = null;
    this.dragEntry = null;
    this.panning = false;
    this.cineTimer = 0;
    this.sim = null;
    this.previewSim = null;
    this.lastSnapshot = null;
    this.labEditing = null;
    this.categoryFilter = null;
  }

  init() {
    this.buildCategoryTabs();
    this.buildPalette();
    this.buildArenaSelect();
    this.buildModifierBar();
    this.buildFactionLegend();
    this.wireTopbar();
    this.wireCanvas();
    this.wirePanels();
    this.wireLab();
    this.refreshConfigList();
    this.updateProgressionUI();

    const autosave = SaveService.getAutosave();
    if (autosave && autosave.mode === 'sandbox') this.config = autosave;
    this.renderer.setArena(this.config.arena);
    $('arenaSelect').value = this.config.arena;
    $('timeLimitInput').value = this.config.timeLimit;
    this.rebuildPreview();
    this.renderer.overview(this.previewSim);
    this.refreshAll();
    this.updateMomentum();

    if (!autosave && this.progression.profile.level === 1) {
      setTimeout(() => this.toast('New here? Hit ⚡ Quick Battle for an instant fight — or pick a unit and click the left half of the field.'), 600);
    }

    window.addEventListener('resize', () => this.resize());
    this.resize();

    this.lastTime = performance.now();
    this.accumulator = 0;
    requestAnimationFrame(t => this.loop(t));
  }

  blankConfig() {
    return {
      mode: 'sandbox',
      arena: 'grassland',
      modifiers: [],
      timeLimit: 90,
      seed: (Math.random() * 0xffffffff) >>> 0,
      budgets: { A: 1000, B: 1000 },
      unitLimit: 40,
      unrestricted: false,
      restrictions: null,
      teams: { A: { units: [] }, B: { units: [] } }
    };
  }

  resize() {
    const r = this.canvas.getBoundingClientRect();
    if (r.width > 0) {
      this.canvas.width = Math.floor(r.width);
      this.canvas.height = Math.floor(r.height);
    }
  }

  // ================= build UI =================
  buildCategoryTabs() {
    const tabs = $('categoryTabs');
    tabs.innerHTML = '';
    const mk = (id, label, color) => {
      const b = document.createElement('button');
      b.textContent = label;
      b.dataset.cat = id;
      if (color) b.style.borderColor = color;
      b.onclick = () => {
        this.categoryFilter = this.categoryFilter === id ? null : id;
        document.querySelectorAll('#categoryTabs button').forEach(x =>
          x.classList.toggle('active', x.dataset.cat === this.categoryFilter));
        this.buildPalette();
      };
      tabs.appendChild(b);
    };
    mk('all', 'All', null);
    for (const [id, c] of Object.entries(CATEGORIES)) mk(id, c.name, c.color);
  }

  buildPalette() {
    const pal = $('unitPalette');
    pal.innerHTML = '';
    for (const u of UNIT_LIST) {
      if (this.categoryFilter && this.categoryFilter !== 'all' && u.category !== this.categoryFilter) continue;
      const restricted = this.config.restrictions && this.config.restrictions.categories &&
        !this.config.restrictions.categories.includes(u.category);
      const card = document.createElement('div');
      card.className = 'unitCard' + (this.selectedType === u.id ? ' selected' : '');
      card.style.opacity = restricted ? 0.4 : 1;
      const cat = CATEGORIES[u.category];
      card.innerHTML =
        '<div class="swatch" style="background:' + u.color + ';border:2px solid ' + u.accent + '"></div>' +
        '<div><div class="uName">' + u.name + '</div>' +
        '<div class="uMeta">' + cat.name + ' · ' + u.hp + ' HP</div></div>' +
        '<div class="uCost">' + u.cost + '</div>';
      card.title = u.desc + (restricted ? '  — RESTRICTED in this mode' : '');
      card.onclick = () => {
        if (restricted) { this.toast('That unit category is restricted in this mode.'); return; }
        this.selectedType = this.selectedType === u.id ? null : u.id;
        this.placingUpgrade = null;
        this.selectedEntry = null;
        this.buildPalette();
        this.showTypeInfo();
      };
      pal.appendChild(card);
    }
  }

  buildArenaSelect() {
    const sel = $('arenaSelect');
    sel.innerHTML = '';
    for (const a of Object.values(ARENAS)) {
      const o = document.createElement('option');
      o.value = a.id;
      o.textContent = a.name;
      sel.appendChild(o);
    }
    sel.value = this.config.arena;
    sel.onchange = () => {
      this.config.arena = sel.value;
      const arena = ARENAS[sel.value];
      this.config.modifiers = arena.modifiers.slice();
      this.renderer.setArena(sel.value);
      this.buildModifierBar();
      this.rebuildPreview();
      this.toast(arena.name + ': ' + arena.blurb);
    };
  }

  buildModifierBar() {
    const bar = $('modifierBar');
    bar.innerHTML = '';
    const arena = ARENAS[this.config.arena];
    const all = [...new Set([...(arena.modifiers || []), 'wind', 'lowGravity', 'slippery'])];
    for (const m of all) {
      const b = document.createElement('button');
      const on = this.config.modifiers.includes(m);
      b.textContent = MODIFIER_INFO[m] ? MODIFIER_INFO[m].name : m;
      b.className = on ? 'active' : '';
      b.title = MODIFIER_INFO[m] ? MODIFIER_INFO[m].desc : m;
      b.style.fontSize = '10px';
      b.onclick = () => {
        const i = this.config.modifiers.indexOf(m);
        if (i >= 0) this.config.modifiers.splice(i, 1);
        else this.config.modifiers.push(m);
        this.buildModifierBar();
      };
      bar.appendChild(b);
    }
  }

  buildFactionLegend() {
    const el = $('factionLegend');
    el.innerHTML = '<b style="color:#aab8cf">Factions</b><br>' + Object.values(FACTIONS)
      .map(f => '<span style="color:' + f.color + '">■ ' + f.name + '</span> — ' + f.bonusText)
      .join('<br>');
  }

  wireTopbar() {
    $('btnStart').onclick = () => this.startBattle();
    $('btnQuick').onclick = () => this.quickBattle();
    $('btnPauseResume').onclick = () => this.togglePause();
    $('btnReset').onclick = () => this.resetBattle();
    $('btnEnd').onclick = () => this.endBattleManual();
    $('speedSelect').onchange = e => { this.speed = parseFloat(e.target.value); };
    $('btnFollow').onclick = () => this.toggleFollow();
    $('btnOverview').onclick = () => {
      this.following = false;
      $('btnFollow').classList.remove('active');
      this.renderer.follow = null;
      this.renderer.overview(this.sim || this.previewSim);
    };
    $('btnSeed').onclick = () => {
      this.config.seed = (Math.random() * 0xffffffff) >>> 0;
      this.toast('New battle seed: ' + this.config.seed);
    };
    $('btnMute').onclick = () => {
      this.audio.muted = !this.audio.muted;
      $('btnMute').textContent = this.audio.muted ? '🔇' : '🔊';
    };

    document.querySelectorAll('#modeTabs .tab').forEach(b => {
      b.onclick = () => this.setMode(b.dataset.mode);
    });

    $('timeLimitInput').onchange = e => {
      this.config.timeLimit = Math.max(20, Math.min(300, parseInt(e.target.value) || 90));
    };

    const unres = document.createElement('button');
    unres.id = 'btnUnrestricted';
    unres.title = 'Unrestricted sandbox: ignore budgets and unit limits';
    unres.textContent = '∞ Unrestricted';
    unres.onclick = () => {
      this.config.unrestricted = !this.config.unrestricted;
      unres.classList.toggle('active', this.config.unrestricted);
      this.refreshBudgetUI();
    };
    $('envControls').insertBefore(unres, $('btnSeed'));
  }

  wirePanels() {
    document.querySelectorAll('#placementTeam .teamBtn').forEach(b => {
      b.onclick = () => {
        this.team = b.dataset.team;
        document.querySelectorAll('#placementTeam .teamBtn').forEach(x => x.classList.toggle('active', x === b));
      };
    });

    document.querySelectorAll('#formationTools button').forEach(b => {
      b.onclick = () => this.applyFormation(b.dataset.form);
    });

    $('btnRandomArmy').onclick = () => this.randomArmies();
    $('btnShareCode').onclick = () => this.shareCode();
    $('btnImportCode').onclick = () => this.importCode();

    $('btnSaveConfig').onclick = async () => {
      if (!this.hasAnyUnits()) { this.toast('Place some units first.'); return; }
      const name = await this.promptModal('Name this setup', 'My Setup');
      if (!name) return;
      SaveService.saveConfig(name, this.config);
      this.refreshConfigList();
      this.toast('Saved "' + name + '".');
    };
    $('btnLoadConfig').onclick = () => {
      const sel = $('configList');
      if (!sel.value) { this.toast('Pick a saved setup first.'); return; }
      const all = SaveService.listConfigs();
      if (all[sel.value]) {
        this.config = all[sel.value].config;
        this.afterConfigReplaced();
        this.toast('Loaded "' + sel.value + '".');
      }
    };
    $('btnDeleteConfig').onclick = () => {
      const sel = $('configList');
      if (!sel.value) return;
      SaveService.deleteConfig(sel.value);
      this.refreshConfigList();
    };

    $('btnAchievements').onclick = () => $('achList').classList.toggle('hidden');
    $('btnRematch').onclick = () => {
      this.config.seed = (Math.random() * 0xffffffff) >>> 0;
      this.resetBattle();
      this.startBattle();
    };
    $('btnEdit').onclick = () => this.editArmies();
    $('btnToLab').onclick = () => this.sendToLab();
    $('btnNextMission').onclick = () => this.nextMission();
    $('btnNextWave').onclick = () => this.nextWave();
  }

  wireLab() {
    $('btnLabNew').onclick = () => {
      if (!this.hasAnyUnits()) { this.toast('Set up armies in the Sandbox first.'); return; }
      this.lab.newExperiment(this.config, 'Experiment ' + new Date().toLocaleDateString());
      this.renderLab();
      this.progression.unlock('lab_rat');
      this.toast('New experiment created from your sandbox setup.');
    };
    $('btnLabFormations').onclick = () => {
      if (!this.lab.experiment) { this.toast('Create or pick an experiment first.'); return; }
      if (this.lab.autoFormations()) {
        this.renderLab();
        this.toast('Formation variants added \u2014 run the experiment to compare.');
      } else {
        this.toast('Formation variants already present (or baseline is empty).');
      }
    };
    $('btnLabSynergy').onclick = () => {
      if (!this.lab.experiment) { this.toast('Create or pick an experiment first.'); return; }
      const n = this.lab.synergyScan();
      this.renderLab();
      this.toast(n ? n + ' synergy variants created \u2014 run the experiment to compare.' : 'Synergy variants already present (or baseline is empty).');
    };
    $('btnLabMatrix').onclick = () => {
      if (this.lab.matrixRunning) { this.toast('A matrix run is already in progress.'); return; }
      const ok = this.lab.runMatrix(6, {},
        p => {
          $('labProgressFill').style.width = (p.total ? (p.done / p.total * 100) : 0) + '%';
          $('labProgressText').textContent = 'Matchups ' + p.done + '/' + p.total + ' (' + p.runs + ' runs each)';
        },
        m => {
          $('labProgressText').textContent = 'Matrix done \u2713';
          this.renderMatrix(m);
          this.addXP(15);
          this.updateProgressionUI();
          this.toast('Matchup Matrix complete \u2014 green means the row unit wins that duel.');
        }
      );
      if (ok) this.toast('Running the 1v1 Matchup Matrix \u2014 every unit versus every other, seeded and reproducible.');
    };
    $('btnLabClose').onclick = () => {
      this.labEditing = null;
      $('labScreen').classList.add('hidden');
      document.querySelector('#layout').classList.remove('hidden');
      document.querySelectorAll('#modeTabs .tab').forEach(x => x.classList.toggle('active', x.dataset.mode === 'sandbox'));
    };
    $('labName').onchange = () => this.lab.setMeta($('labName').value, null);
    $('labNotes').onchange = () => this.lab.setMeta(null, $('labNotes').value);
    $('btnLabRun').onclick = () => {
      const runs = parseInt($('labRuns').value) || 10;
      const ok = this.lab.runAll(
        runs,
        (p) => {
          $('labProgressFill').style.width = (p.total ? (p.done / p.total * 100) : 0) + '%';
          $('labProgressText').textContent = p.done + '/' + p.total + ' battles';
        },
        () => {
          $('labProgressText').textContent = 'Done ✓';
          this.renderLab();
          const p = this.progression.profile;
          p.__labRuns = (p.__labRuns || 0) + runs;
          this.progression.save();
          if (p.__labRuns >= 10) this.progression.unlock('scientist');
          this.addXP(runs * 3);
          this.updateProgressionUI();
        }
      );
      if (!ok) this.toast('An experiment is already running.');
    };
  }

  // ================= canvas input =================
  wireCanvas() {
    const c = this.canvas;
    c.addEventListener('mousemove', e => {
      const w = this.renderer.screenToWorld(e.offsetX, e.offsetY);
      this.hoverWorld = w;
      if (this.dragEntry) {
        this.dragEntry.__entry.x = this.clampToHalf(w.x, this.dragEntry.team);
        this.dragEntry.__entry.y = Math.max(20, Math.min(WORLD.H - 20, w.y));
        this.rebuildPreview();
      } else if (this.panning) {
        this.renderer.targetCam.x -= e.movementX / this.renderer.cam.zoom;
        this.renderer.targetCam.y -= e.movementY / this.renderer.cam.zoom;
        this.renderer.cam.x = this.renderer.targetCam.x;
        this.renderer.cam.y = this.renderer.targetCam.y;
      }
    });
    c.addEventListener('mousedown', e => {
      this.audio.ensure();
      const w = this.renderer.screenToWorld(e.offsetX, e.offsetY);
      if (e.button === 1 || e.button === 2 || (e.button === 0 && e.shiftKey)) {
        this.panning = true;
        e.preventDefault();
        return;
      }
      if (e.button !== 0) return;
      if (this.phase === 'setup') this.handleSetupClick(w, e);
      else this.handleBattleClick(w);
    });
    c.addEventListener('mouseup', () => {
      if (this.dragEntry) this.saveAutosave();
      this.dragEntry = null;
      this.panning = false;
    });
    c.addEventListener('mouseleave', () => {
      this.hoverWorld = null;
      this.dragEntry = null;
      this.panning = false;
    });
    c.addEventListener('contextmenu', e => {
      e.preventDefault();
      const w = this.renderer.screenToWorld(e.offsetX, e.offsetY);
      if (this.phase === 'setup') {
        const entry = this.entryAt(w);
        if (entry) { this.removeUnit(entry); this.audio.remove(); }
      }
    });
    c.addEventListener('wheel', e => {
      e.preventDefault();
      const f = e.deltaY < 0 ? 1.12 : 0.9;
      const before = this.renderer.screenToWorld(e.offsetX, e.offsetY);
      this.renderer.cam.zoom = Math.max(0.25, Math.min(3, this.renderer.cam.zoom * f));
      this.renderer.targetCam.zoom = this.renderer.cam.zoom;
      const after = this.renderer.screenToWorld(e.offsetX, e.offsetY);
      this.renderer.cam.x += before.x - after.x;
      this.renderer.cam.y += before.y - after.y;
      this.renderer.targetCam.x = this.renderer.cam.x;
      this.renderer.targetCam.y = this.renderer.cam.y;
    }, { passive: false });

    window.addEventListener('keydown', e => {
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') return;
      if (e.code === 'Space') {
        e.preventDefault();
        if (this.phase === 'setup') this.startBattle();
        else this.togglePause();
      } else if (e.key === 'r' || e.key === 'R') this.resetBattle();
      else if (e.key === 'o' || e.key === 'O') {
        this.following = false;
        this.renderer.follow = null;
        this.renderer.overview(this.sim || this.previewSim);
      } else if (e.key === 'Delete' && this.selectedEntry && this.phase === 'setup') {
        this.removeUnit(this.selectedEntry);
      }
    });
  }

  handleSetupClick(w, e) {
    const entry = this.entryAt(w);
    if (entry) {
      if (e.altKey) {
        if (!this.canAfford(entry.team, unitCost(entry.type))) { this.toast('Not enough budget to duplicate.'); return; }
        this.config.teams[entry.team].units.push({ type: entry.type, x: entry.x + 30, y: entry.y + 30, upgrade: entry.upgrade });
        this.rebuildPreview();
        this.refreshBudgetUI();
        this.audio.place();
        return;
      }
      this.selectedEntry = entry.__entry;
      this.selectedType = null;
      this.dragEntry = entry;
      this.buildPalette();
      this.showPlacedInfo(entry);
      return;
    }
    if (this.selectedType) {
      this.tryPlace(this.selectedType, w);
    } else {
      this.selectedEntry = null;
      this.showTypeInfo();
    }
  }

  handleBattleClick(w) {
    let best = null, bd = 40;
    for (const u of (this.sim ? this.sim.units : [])) {
      if (!u.alive) continue;
      const d = Math.hypot(u.x - w.x, u.y - w.y);
      if (d < bd) { bd = d; best = u; }
    }
    if (best) {
      this.selectedUnit = best;
      if (this.following) this.renderer.follow = best;
      this.toast(best.def.name + ' — ' + Math.round(best.hp) + '/' + best.maxHp + ' HP · Team ' + (best.team === 'A' ? 'Azure' : 'Crimson'));
    }
  }

  entryAt(w) {
    let best = null, bd = Infinity;
    for (const team of ['A', 'B']) {
      for (const entry of this.config.teams[team].units) {
        const def = resolveDef(entry.type, entry.upgrade);
        const d = Math.hypot(entry.x - w.x, entry.y - w.y);
        if (d < Math.max(24, def.radius + 8) && d < bd) { bd = d; best = Object.assign({}, entry, { team, __entry: entry }); }
      }
    }
    return best;
  }

  clampToHalf(x, team) {
    if (this.config.unrestricted) return Math.max(20, Math.min(WORLD.W - 20, x));
    return team === 'A'
      ? Math.max(20, Math.min(WORLD.W / 2 - 40, x))
      : Math.max(WORLD.W / 2 + 40, Math.min(WORLD.W - 20, x));
  }

  tryPlace(type, w) {
    const team = this.team;
    const def = resolveDef(type, this.placingUpgrade);
    const cost = def.cost;
    if (!this.canAfford(team, cost)) { this.toast('Not enough budget!'); return; }
    const teamUnits = this.config.teams[team].units;
    if (!this.config.unrestricted && teamUnits.length >= this.config.unitLimit) {
      this.toast('Unit limit reached (' + this.config.unitLimit + ').');
      return;
    }
    const entry = {
      type,
      x: this.clampToHalf(w.x, team),
      y: Math.max(20, Math.min(WORLD.H - 20, w.y)),
      upgrade: this.placingUpgrade
    };
    teamUnits.push(entry);
    this.audio.place();
    this.rebuildPreview();
    this.refreshBudgetUI();
    this.selectedEntry = entry;
    this.showPlacedInfo(Object.assign({}, entry, { team, __entry: entry }));
  }

  removeUnit(entryWrapper) {
    const team = entryWrapper.team || 'A';
    const arr = this.config.teams[team].units;
    const target = entryWrapper.__entry || entryWrapper;
    const i = arr.indexOf(target);
    if (i >= 0) arr.splice(i, 1);
    if (this.selectedEntry === target) this.selectedEntry = null;
    this.rebuildPreview();
    this.refreshBudgetUI();
    this.showTypeInfo();
  }

  canAfford(team, cost) {
    if (this.config.unrestricted) return true;
    return this.spentBy(team) + cost <= this.config.budgets[team];
  }

  spentBy(team) {
    return this.config.teams[team].units.reduce((s, u) => s + unitCost(u.type), 0);
  }

  hasAnyUnits() {
    return this.config.teams.A.units.length + this.config.teams.B.units.length > 0;
  }

  saveAutosave() {
    if (this.phase === 'setup' && this.mode === 'sandbox') SaveService.setAutosave(this.config);
  }

  afterConfigReplaced() {
    this.renderer.setArena(this.config.arena);
    $('arenaSelect').value = this.config.arena;
    $('timeLimitInput').value = this.config.timeLimit;
    this.buildModifierBar();
    this.buildPalette();
    this.rebuildPreview();
    this.renderer.overview(this.previewSim);
    this.refreshBudgetUI();
    this.updateMomentum();
    this.selectedEntry = null;
    this.showTypeInfo();
  }

  // ================= formations =================
  applyFormation(form) {
    if (this.phase !== 'setup') { this.toast('Only during placement.'); return; }
    const W = WORLD.W, H = WORLD.H;
    if (form === 'clear') {
      this.config.teams[this.team].units = [];
      this.rebuildPreview(); this.refreshBudgetUI(); this.showTypeInfo();
      return;
    }
    if (form === 'mirror') {
      this.config.teams.B.units = this.config.teams.A.units.map(u => Object.assign({}, u, { x: W - u.x }));
      this.rebuildPreview(); this.refreshBudgetUI();
      this.toast('Mirrored Team Azure onto Team Crimson.');
      return;
    }
    const units = this.config.teams[this.team].units;
    if (!units.length) return;
    const dir = this.team === 'A' ? 1 : -1;
    const cx = units.reduce((s, u) => s + u.x, 0) / units.length;
    const anchorX = this.team === 'A'
      ? Math.max(W * 0.20, Math.min(cx, W * 0.36))
      : Math.min(W * 0.80, Math.max(cx, W * 0.64));

    const rank = t => {
      const cat = resolveDef(t.type, t.upgrade).category;
      if (cat === 'frontline' || cat === 'heavy') return 0;
      if (cat === 'agile' || cat === 'specialist') return 1;
      if (cat === 'ranged') return 2;
      return 3;
    };
    const sorted = units.slice().sort((a, b) => rank(a) - rank(b));
    const rng = new RNG(this.config.seed);

    if (form === 'line' || form === 'wall') {
      const spacing = form === 'wall' ? 46 : 80;
      const rows = {};
      sorted.forEach(u => { (rows[rank(u)] || (rows[rank(u)] = [])).push(u); });
      const rankOrder = Object.keys(rows).map(Number).sort((a, b) => a - b);
      let rowsUsed = 0;
      for (const r of rankOrder) {
        const list = rows[r];
        list.forEach((u, i) => {
          u.x = this.clampToHalf(anchorX + dir * rowsUsed * (form === 'wall' ? 40 : 66), this.team);
          u.y = H / 2 + (i - (list.length - 1) / 2) * spacing;
        });
        rowsUsed++;
      }
    } else if (form === 'wedge') {
      sorted.forEach((u, i) => {
        const row = Math.floor(i / 2);
        const side = i % 2 === 0 ? 1 : -1;
        u.x = this.clampToHalf(anchorX + dir * row * 60, this.team);
        u.y = H / 2 + side * (row + 1) * 55;
      });
    } else if (form === 'spread') {
      sorted.forEach(u => {
        u.x = this.clampToHalf(anchorX + rng.range(-220, 220), this.team);
        u.y = Math.max(50, Math.min(H - 50, H / 2 + rng.range(-330, 330)));
      });
    }
    this.rebuildPreview();
    this.refreshBudgetUI();
    this.saveAutosave();
  }

  randomArmies() {
    if (this.phase !== 'setup') return;
    const rng = new RNG((Math.random() * 0xffffffff) >>> 0);
    const budget = this.config.unrestricted ? 1000 : this.config.budgets.A;
    for (const team of ['A', 'B']) {
      const result = randomArmy(budget, rng, this.config.restrictions || {});
      this.config.teams[team].units = layoutArmy(result.picks, team, { W: WORLD.W, H: WORLD.H }, rng, rng.pick(['defensive', 'balanced', 'scattered']));
    }
    this.rebuildPreview();
    this.refreshBudgetUI();
    this.toast('Random armies generated. Tweak and battle!');
  }

  // One click: fresh arena + two random armies + battle starts immediately.
  quickBattle() {
    if (this.phase === 'battle') return;
    const rng = new RNG((Math.random() * 0xffffffff) >>> 0);
    if (this.phase === 'results') this.resetBattle();
    this.mode = 'sandbox';
    const arenaId = rng.pick(Object.keys(ARENAS).filter(a => this.progression.profile.level >= (ARENAS[a].unlockLevel || 0))) || 'grassland';
    this.config = this.blankConfig();
    this.config.arena = arenaId;
    this.config.modifiers = [...(ARENAS[arenaId].modifiers || [])];
    this.config.budgets = { A: 450, B: 450 };
    const budget = 450;
    for (const team of ['A', 'B']) {
      const result = randomArmy(budget, rng, {});
      this.config.teams[team].units = layoutArmy(result.picks, team, { W: WORLD.W, H: WORLD.H }, rng, rng.pick(['defensive', 'balanced', 'scattered']));
    }
    this.buildPalette();
    this.buildModifierBar();
    this.rebuildPreview();
    this.refreshBudgetUI();
    this.renderer.setArena(arenaId);
    $('arenaSelect').value = arenaId;
    this.config.seed = (Math.random() * 0xffffffff) >>> 0;
    this.startBattle();
  }

  // Live momentum: cost-weighted remaining army strength, 0-100 in Azure's favor.
  updateMomentum() {
    const bar = $('momentumA');
    if (!bar) return;
    const power = sim => {
      if (!sim) return { A: 1, B: 1 };
      let a = 0.001, b = 0.001;
      for (const u of sim.units) {
        if (!u.alive || u.isDecoy) continue;
        const v = u.def.cost * (u.hp / u.maxHp);
        if (u.team === 'A') a += v; else b += v;
      }
      return { A: a, B: b };
    };
    const p = power(this.phase === 'battle' || this.phase === 'results' ? this.sim : this.previewSim);
    const pct = Math.round(100 * p.A / (p.A + p.B));
    bar.style.setProperty('--mom', pct);
    bar.style.clipPath = `inset(0 ${100 - pct}% 0 0)`;
    $('momA').textContent = pct + '%';
    $('momB').textContent = (100 - pct) + '%';
  }

  // ---- share codes: portable battle configurations ----
  static CODE_PREFIX = 'UC1.';
  encodeConfig(config) {
    try {
      const json = JSON.stringify(config);
      return 'UC1.' + btoa(unescape(encodeURIComponent(json)));
    } catch { return null; }
  }
  decodeConfig(code) {
    try {
      const body = code.trim().replace(/^UC1\./, '');
      const json = decodeURIComponent(escape(atob(body)));
      const cfg = JSON.parse(json);
      if (!cfg || !cfg.teams || !cfg.teams.A || !cfg.teams.B) return null;
      return cfg;
    } catch { return null; }
  }
  async shareCode() {
    if (!this.hasAnyUnits()) { this.toast('Place some units first.'); return; }
    const code = this.encodeConfig(this.config);
    if (!code) { this.toast('Could not encode this setup.'); return; }
    try {
      await navigator.clipboard.writeText(code);
      this.toast('Battle code copied \u2014 paste it anywhere to share.');
    } catch {
      await this.promptModal('Copy this battle code', code);
      this.toast('Select all and copy the code.');
    }
  }
  async importCode() {
    const code = await this.promptModal('Paste a battle code', '');
    if (!code) return;
    const cfg = this.decodeConfig(code);
    if (!cfg) { this.toast('That code could not be read.'); return; }
    this.config = cfg;
    this.afterConfigReplaced();
    this.toast('Battle imported \u2014 press Start.');
  }

  // ================= battle control =================
  startBattle() {
    if (this.phase === 'battle') return;
    if (!this.hasAnyUnits()) { this.toast('Place at least one unit first.'); return; }
    this.hideResults();
    this.phase = 'battle';
    this.paused = false;
    this.cineTimer = 0;
    this.following = false;
    $('btnFollow').classList.remove('active');
    const cfg = cloneConfig(this.config);
    cfg.collectEvents = true;
    this.sim = new BattleSim(cfg);
    this.renderer.follow = null;
    this.renderer.setArena(this.config.arena);
    this.renderer.overview(this.sim);
    this.audio.start();

    $('btnStart').disabled = true;
    $('btnPauseResume').disabled = false;
    $('btnReset').disabled = false;
    $('btnEnd').disabled = false;
    $('hint').textContent = 'Click a unit to inspect. Follow locks the camera onto it.';

    const usedTypes = [...this.config.teams.A.units, ...this.config.teams.B.units].map(u => u.type);
    this.progression.recordUnitUse(usedTypes);
    this.updateProgressionUI();
  }

  togglePause() {
    if (this.phase !== 'battle') return;
    this.paused = !this.paused;
    $('btnPauseResume').textContent = this.paused ? '▶ Resume' : '⏸ Pause';
  }

  resetBattle() {
    this.sim = null;
    this.phase = 'setup';
    this.paused = false;
    this.hideResults();
    $('btnStart').disabled = false;
    $('btnPauseResume').disabled = true;
    $('btnPauseResume').textContent = '⏸ Pause';
    $('btnReset').disabled = true;
    $('btnEnd').disabled = true;
    $('battleStatus').textContent = '';
    this.rebuildPreview();
    this.renderer.overview(this.previewSim);
    this.renderer.follow = null;
    this.updateMomentum();
  }

  endBattleManual() {
    if (!this.sim || this.sim.outcome) return;
    const a = this.sim.aliveOf('A'), b = this.sim.aliveOf('B');
    this.sim.outcome = {
      winner: a > b ? 'A' : b > a ? 'B' : 'draw',
      reason: 'manual', duration: this.sim.t
    };
    this.finishBattle();
  }

  editArmies() {
    this.resetBattle();
  }

  toggleFollow() {
    this.following = !this.following;
    $('btnFollow').classList.toggle('active', this.following);
    this.renderer.follow = this.following && this.selectedUnit ? this.selectedUnit : null;
  }

  // ================= loop =================
  loop(now) {
    const dt = Math.min(0.1, (now - this.lastTime) / 1000);
    this.lastTime = now;

    if (this.phase === 'battle' && this.sim && !this.paused) {
      const spd = this.cineTimer > 0 ? 0.3 : this.speed;
      this.accumulator += dt * spd;
      let steps = 0;
      while (this.accumulator >= 1 / 30 && steps < 20) {
        this.sim.step();
        this.accumulator -= 1 / 30;
        steps++;
        if (this.sim.outcome) break;
      }
      const events = this.sim.drainEvents();
      this.renderer.consumeEvents(events);
      this.playEventAudio(events);

      if (this.sim.outcome && this.cineTimer === 0) {
        this.cineTimer = 1.4;
        const dead = this.sim.units.filter(u => !u.alive).sort((a, b) => b.deathT - a.deathT)[0];
        if (dead) {
          this.renderer.targetCam.x = dead.x;
          this.renderer.targetCam.y = dead.y;
          this.renderer.targetCam.zoom = Math.max(this.renderer.cam.zoom, 1.4);
        }
      }
      if (this.cineTimer > 0) {
        this.cineTimer -= dt;
        if (this.cineTimer <= 0) this.finishBattle();
      }
      $('battleStatus').textContent = this.sim.t.toFixed(1) + 's · Azure ' + this.sim.aliveOf('A') + ' vs Crimson ' + this.sim.aliveOf('B');
      this.updateMomentum();
    }

    this.renderer.updateFx(dt);
    const drawSim = this.sim && (this.phase === 'battle' || this.phase === 'results') ? this.sim : this.previewSim;
    const ghost = (this.phase === 'setup' && this.selectedType && this.hoverWorld && !this.dragEntry)
      ? {
          x: this.clampToHalf(this.hoverWorld.x, this.team),
          y: this.hoverWorld.y,
          def: resolveDef(this.selectedType, this.placingUpgrade),
          team: this.team
        }
      : null;
    this.renderer.render(drawSim, {
      phase: this.phase,
      selected: this.selectedUnit,
      ghost,
      alwaysBars: false
    });
    requestAnimationFrame(t => this.loop(t));
  }

  playEventAudio(events) {
    for (const ev of events) {
      switch (ev.type) {
        case 'hit': if (ev.crit) this.audio.crit(); else this.audio.hit(); break;
        case 'shot': this.audio.shot(); break;
        case 'death': this.audio.death(); break;
        case 'heal': this.audio.heal(); break;
        case 'ability': this.audio.ability(); break;
      }
    }
  }

  // ================= results =================
  finishBattle() {
    if (this.phase === 'results') return;
    this.phase = 'results';
    this.lastSnapshot = this.sim.stats.snapshot();
    const snap = this.lastSnapshot;
    const winner = this.sim.outcome.winner;
    const reason = this.sim.outcome.reason;
    this.updateMomentum();

    if (winner === 'B' && this.mode !== 'sandbox') this.audio.defeat();
    else this.audio.victory();

    let xp = 25;
    if (winner !== 'draw') xp += winner === 'A' ? 40 : 15;
    xp += Math.round((snap.team.A.damageDealt + snap.team.A.healing) / 20);
    const leveled = this.addXP(xp);
    this.checkAchievements(snap);
    this.updateProgressionUI();

    const insights = generateInsights(snap);
    const mvp = snap.units.slice().sort((a, b) =>
      (b.damageDealt + b.healing * 1.2 + b.kills * 30) - (a.damageDealt + a.healing * 1.2 + a.kills * 30))[0];
    const col = winner === 'A' ? 'blue' : winner === 'B' ? 'red' : 'gold';
    const title = winner === 'draw' ? 'STALEMATE' : (winner === 'A' ? 'TEAM AZURE WINS' : 'TEAM CRIMSON WINS');
    const reasonText = {
      annihilation: 'Total annihilation',
      timeout: 'Time limit — stronger army remains',
      manual: 'Battle ended manually',
      mutual: 'Mutual destruction'
    }[reason] || '';

    let html = '<h2 class="' + col + '">' + title + '</h2>' +
      '<div class="dim">' + reasonText + ' · Duration ' + this.sim.t.toFixed(1) + 's · +' + xp + ' XP' +
      (leveled ? ' · <b style="color:var(--gold)">LEVEL UP → ' + this.progression.profile.level + '</b>' : '') + '</div>' +
      '<div class="resultCols">';

    for (const t of ['A', 'B']) {
      const ts = snap.team[t];
      const label = t === 'A' ? 'Team Azure' : 'Team Crimson';
      html += '<div>' +
        '<div class="statLine"><b style="color:' + (t === 'A' ? 'var(--accent)' : 'var(--accent2)') + '">' + label + '</b><span class="dim">' + (winner === t ? 'WINNER' : '') + '</span></div>' +
        '<div class="statLine"><span>Damage dealt</span><b>' + Math.round(ts.damageDealt) + '</b></div>' +
        '<div class="statLine"><span>Damage taken</span><b>' + Math.round(ts.damageTaken) + '</b></div>' +
        '<div class="statLine"><span>Healing</span><b>' + Math.round(ts.healing) + '</b></div>' +
        '<div class="statLine"><span>Healing received</span><b>' + Math.round(ts.healingRecv || 0) + '</b></div>' +
        '<div class="statLine"><span>Kills / Lost</span><b>' + ts.kills + ' / ' + ts.lost + '</b></div>' +
        '<div class="statLine"><span>Survivors</span><b>' + this.sim.aliveOf(t) + '</b></div>' +
        '</div>';
    }
    html += '</div>';
    html += this.timelineSVG(snap);

    if (mvp && (mvp.damageDealt > 20 || mvp.healing > 20)) {
      html += '<div class="insightItem">⭐ MVP: <b>' + mvp.name + '</b> (' + (mvp.team === 'A' ? 'Azure' : 'Crimson') + ') — ' +
        Math.round(mvp.damageDealt) + ' dmg, ' + mvp.kills + ' kills' +
        (mvp.healing > 5 ? ', ' + Math.round(mvp.healing) + ' healing' : '') + '</div>';
    }
    if (insights.length) {
      html += '<h3 style="margin:10px 0 4px;font-size:13px;color:var(--dim)">BATTLE INSIGHTS</h3>';
      html += insights.map(i => '<div class="insightItem">' + i.text + '</div>').join('');
      html += '<div class="dim small" style="margin-top:6px">Improve on it: "Send to Battle Lab" → Duplicate the config → change ONE thing → run 10 battles → compare.</div>';
    }

    $('resultsContent').innerHTML = html;
    $('btnNextMission').classList.toggle('hidden', !(this.mode === 'campaign' && winner === 'A'));
    $('btnNextWave').classList.toggle('hidden', !(this.mode === 'survival' && winner === 'A'));
    $('resultsPanel').classList.remove('hidden');

    if (this.mode === 'campaign' && winner === 'A') {
      this.progression.profile.campaignProgress = Math.max(this.progression.profile.campaignProgress, this.campaignIndex + 1);
      this.progression.save();
      this.addXP(50);
      this.toast('Mission complete! Campaign progress saved.');
      if (this.campaignIndex === CAMPAIGN.length - 1) this.progression.unlock('campaigner');
    }
    if (this.mode === 'survival' && winner === 'A' && this.survival.wave >= 5) {
      this.progression.unlock('survivor5');
    }
    this.saveAutosave();
  }

  // Kill-flow chart: alive unit count per team over the whole battle.
  timelineSVG(snap) {
    const startA = snap.units.filter(u => u.team === 'A').length;
    const startB = snap.units.filter(u => u.team === 'B').length;
    if (!startA && !startB) return '';
    const dur = Math.max(0.1, snap.duration);
    const W = 560, H = 88, PAD = 4;
    let a = startA, b = startB;
    const pts = [[0, a, b]];
    for (const ev of snap.timeline) {
      if (ev.type !== 'death') continue;
      if (ev.team === 'A') a--; else b--;
      pts.push([ev.t, a, b]);
    }
    pts.push([dur, a, b]);
    const mx = 1 / (startA + startB || 1);
    const line = (idx, start) => {
      let d = `M ${(0 / dur) * (W - PAD * 2) + PAD},${H - PAD - ((start * mx) * (H - PAD * 2))}`;
      for (const [t, av, bv] of pts) {
        const v = idx === 0 ? av : bv;
        const y = H - PAD - (v * mx) * (H - PAD * 2);
        d += ` L ${(t / dur) * (W - PAD * 2) + PAD},${y.toFixed(1)}`;
      }
      return d;
    };
    return '<div style="margin-top:10px"><h3 style="font-size:13px;color:var(--dim);margin:0 0 2px">BATTLE FLOW \u2014 UNITS ALIVE</h3>' +
      '<svg width="100%" viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none" style="background:#0d1119;border:1px solid var(--line);border-radius:6px">' +
      '<path d="' + line(0, startA) + '" fill="none" stroke="var(--accent)" stroke-width="2"/>' +
      '<path d="' + line(1, startB) + '" fill="none" stroke="var(--accent2)" stroke-width="2"/>' +
      '</svg><div class="dim small">Azure (blue) vs Crimson (red) \u2014 drops mark eliminations.</div></div>';
  }

  checkAchievements(snap) {
    const p = this.progression;
    const winner = this.sim.outcome.winner;
    const before = p.profile.achievements.length;
    if (winner !== 'draw') p.unlock('first_blood');
    if (winner === 'A') {
      const cost = configCost(this.config);
      if (cost.B - cost.A >= 200) p.unlock('underdog');
      if ((this.config.teams.B.units || []).some(u => u.type === 'colossus')) p.unlock('big_game');
      const cats = new Set(this.config.teams.A.units.map(u => resolveDef(u.type, u.upgrade).category));
      if (cats.size >= 7) p.unlock('allrounder');
    }
    if (p.allUnitsFielded()) p.unlock('collector');
    if (p.profile.achievements.length > before) {
      const a = ACHIEVEMENTS.find(x => x.id === p.profile.achievements[p.profile.achievements.length - 1]);
      if (a) this.toast('🏆 Achievement: ' + a.name + ' — ' + a.desc);
    }
  }

  addXP(amount) {
    const leveled = this.progression.addXP(amount);
    if (leveled) this.toast('Level up! Commander level ' + this.progression.profile.level + '.');
    return leveled;
  }

  hideResults() {
    $('resultsPanel').classList.add('hidden');
  }

  // ================= modes =================
  setMode(mode) {
    if (mode === 'lab') {
      this.openLab();
      return;
    }
    this.mode = mode;
    this.labEditing = null;
    document.querySelectorAll('#modeTabs .tab').forEach(b => b.classList.toggle('active', b.dataset.mode === mode));
    this.resetBattle();

    if (mode === 'sandbox') {
      this.config = this.blankConfig();
      const autosave = SaveService.getAutosave();
      if (autosave && autosave.mode === 'sandbox') {
        this.config = autosave;
        this.config.mode = 'sandbox';
      }
      this.afterConfigReplaced();
      $('modeBanner').classList.add('hidden');
    } else if (mode === 'campaign') {
      this.loadMission(Math.min(this.campaignIndex, CAMPAIGN.length - 1));
    } else if (mode === 'daily') {
      this.loadDaily();
    } else if (mode === 'survival') {
      this.startSurvival();
    }
  }

  loadMission(index) {
    this.campaignIndex = index;
    const m = CAMPAIGN[index];
    this.config = this.blankConfig();
    this.config.mode = 'campaign';
    this.config.arena = m.arena;
    this.config.modifiers = ARENAS[m.arena].modifiers.slice();
    this.config.budgets = { A: m.playerBudget, B: m.enemyBudget };
    this.config.restrictions = m.restrictions || null;
    this.config.timeLimit = 90;
    const enemy = generateEnemyFor(m, (Math.random() * 0xffffffff) >>> 0);
    this.config.teams = { A: { units: [] }, B: { units: enemy } };
    this.afterConfigReplaced();
    const banner = $('modeBanner');
    banner.innerHTML = '<b>Campaign ' + (index + 1) + '/' + CAMPAIGN.length + ': ' + m.name + '</b> — ' + m.desc +
      ' <span class="dim">Tip: ' + m.tip + '</span>';
    banner.classList.remove('hidden');
    this.refreshBudgetUI();
  }

  nextMission() {
    if (this.campaignIndex < CAMPAIGN.length - 1) {
      this.loadMission(this.campaignIndex + 1);
      this.resetBattle();
    } else {
      this.toast('Campaign complete! Sandbox and Battle Lab await.');
    }
  }

  loadDaily() {
    const dateStr = new Date().toISOString().slice(0, 10);
    const d = dailyChallenge(dateStr);
    this.config = this.blankConfig();
    this.config.mode = 'daily';
    this.config.arena = d.arena;
    this.config.modifiers = d.modifiers.slice();
    this.config.budgets = { A: d.playerBudget, B: 9999 };
    this.config.restrictions = d.restrictions;
    this.config.seed = d.seed;
    this.config.teams = { A: { units: [] }, B: { units: d.enemy } };
    this.afterConfigReplaced();
    const banner = $('modeBanner');
    banner.innerHTML = '<b>' + d.name + '</b> — ' + d.desc;
    banner.classList.remove('hidden');
    this.refreshBudgetUI();
  }

  startSurvival() {
    this.survival = { wave: 1, playerUnits: [] };
    this.config = this.blankConfig();
    this.config.mode = 'survival';
    this.config.budgets = { A: 500, B: 9999 };
    this.config.timeLimit = 120;
    this.config.teams = { A: { units: [] }, B: { units: [] } };
    this.spawnWave(1);
    this.afterConfigReplaced();
    const banner = $('modeBanner');
    banner.innerHTML = '<b>Survival — Wave 1</b>. Place your army on the left, then Start. You earn budget between waves; survivors keep their wounds.';
    banner.classList.remove('hidden');
    this.refreshBudgetUI();
  }

  spawnWave(wave) {
    const rng = new RNG((this.config.seed ^ (wave * 2654435761)) >>> 0);
    const budget = 220 + wave * 140;
    const result = randomArmy(budget, rng);
    this.config.teams.B.units = layoutArmy(result.picks, 'B', { W: WORLD.W, H: WORLD.H }, rng, 'balanced');
  }

  nextWave() {
    const survivors = [];
    if (this.sim) {
      for (const u of this.sim.units) {
        if (u.alive && u.team === 'A' && !u.isDecoy) {
          survivors.push({ type: u.def.id, x: u.x, y: u.y, upgrade: u.def.upgrade || null, hpFrac: u.hp / u.maxHp });
        }
      }
    }
    this.survival.wave++;
    const income = 200 + this.survival.wave * 40;
    this.resetBattle();
    this.config.budgets = { A: (this.config.budgets.A || 500) + income, B: 9999 };
    this.config.teams.A.units = survivors.map(s => ({ type: s.type, x: s.x, y: s.y, upgrade: s.upgrade, hpFrac: s.hpFrac }));
    this.spawnWave(this.survival.wave);
    this.afterConfigReplaced();
    const banner = $('modeBanner');
    banner.innerHTML = '<b>Survival — Wave ' + this.survival.wave + '</b>. Income +' + income +
      '. Survivors kept their wounds. Reinforce and press Start.';
    banner.classList.remove('hidden');
    this.refreshBudgetUI();
    this.toast('Wave cleared! +' + income + ' budget.');
  }

  // ================= battle lab screen =================
  openLab() {
    document.querySelectorAll('#modeTabs .tab').forEach(b => b.classList.toggle('active', b.dataset.mode === 'lab'));
    $('labScreen').classList.remove('hidden');
    $('modeBanner').classList.add('hidden');
    this.renderLab();
  }

  renderLab() {
    const exp = this.lab.experiment;
    if (!exp) {
      $('labConfigs').innerHTML = '<div class="dim">Create a new experiment from your sandbox setup, or load one from history.<br><br>Workflow: build a battle → New Experiment → Duplicate → change ONE thing → Run → compare.</div>';
      $('labComparison').innerHTML = '';
      $('labInsights').innerHTML = '';
      this.renderLabHistory();
      return;
    }
    $('labName').value = exp.name;
    $('labNotes').value = exp.notes || '';

    $('labConfigs').innerHTML = exp.configs.map(c => {
      const cost = configCost(c.config);
      const unitsA = (c.config.teams && c.config.teams.A ? c.config.teams.A.units : []).length;
      const unitsB = (c.config.teams && c.config.teams.B ? c.config.teams.B.units : []).length;
      const compA = this.compSummary(c.config.teams && c.config.teams.A ? c.config.teams.A.units : []);
      const r = c.results;
      let resHtml = '<div class="dim small">Not run yet.</div>';
      if (r && r.agg) {
        const a = r.agg;
        const wrA = Math.round(a.winsA / a.runs * 100);
        const wrB = Math.round(a.winsB / a.runs * 100);
        const dr = a.runs - a.winsA - a.winsB;
        resHtml =
          '<div class="winBar" title="Azure ' + wrA + '% · Crimson ' + wrB + '%">' +
          '<div class="wA" style="width:' + wrA + '%"></div></div>' +
          '<span class="miniStat">Azure wins <b>' + wrA + '%</b></span>' +
          '<span class="miniStat">Crimson wins <b>' + wrB + '%</b></span>' +
          (dr ? '<span class="miniStat">Draws <b>' + Math.round(dr / a.runs * 100) + '%</b></span>' : '') +
          '<span class="miniStat">Avg duration <b>' + a.avgDuration.toFixed(1) + 's</b></span>' +
          '<span class="miniStat">Avg survivors <b>' + a.avgSurvivorsA.toFixed(1) + ' / ' + a.avgSurvivorsB.toFixed(1) + '</b></span>' +
          '<span class="miniStat">Avg dmg <b>' + Math.round(a.avgDamageA) + ' / ' + Math.round(a.avgDamageB) + '</b></span>';
      }
      const baselineBadge = c.id === exp.configs[0].id
        ? '<span class="badge" style="background:var(--gold);color:#222;border-radius:6px;padding:1px 6px;font-size:10px">BASELINE</span>' : '';
      return '<div class="labCard" data-cfg="' + c.id + '">' +
        '<h4>' + c.name + ' ' + baselineBadge + '</h4>' +
        '<div class="cfgMeta">Azure: ' + unitsA + ' units, ' + cost.A + ' cost (' + compA + ') · Crimson: ' + unitsB +
        ' units, ' + cost.B + ' cost · Arena: ' + ARENAS[c.config.arena].name +
        (c.config.modifiers.length ? ' +' + c.config.modifiers.join(', ') : '') + '</div>' +
        resHtml +
        '<div class="row">' +
        '<button data-act="edit" class="small">✎ Edit in Sandbox</button>' +
        '<button data-act="dup" class="small">⧉ Duplicate</button>' +
        '<button data-act="del" class="small"' + (exp.configs.length <= 1 ? ' disabled' : '') + '>🗑 Remove</button>' +
        '</div></div>';
    }).join('');

    $('labConfigs').querySelectorAll('.labCard').forEach(card => {
      const cfgId = card.dataset.cfg;
      card.querySelectorAll('button').forEach(b => {
        b.onclick = () => {
          const act = b.dataset.act;
          if (act === 'dup') {
            this.lab.duplicateConfig(cfgId);
            this.toast('Duplicated. Change ONE thing, then run the experiment.');
          } else if (act === 'del') {
            this.lab.removeConfig(cfgId);
          } else if (act === 'edit') {
            const cfg = this.lab.experiment.configs.find(c => c.id === cfgId);
            this.labEditing = cfgId;
            this.config = cloneConfig(cfg.config);
            $('labScreen').classList.add('hidden');
            document.querySelector('#layout').classList.remove('hidden');
            document.querySelectorAll('#modeTabs .tab').forEach(x => x.classList.toggle('active', x.dataset.mode === 'sandbox'));
            this.afterConfigReplaced();
            const banner = $('modeBanner');
            banner.innerHTML = '<b>Editing Battle Lab config</b> — <button id="labReturn" style="margin:0 6px">Save & Return to Lab</button> when done.';
            banner.classList.remove('hidden');
            $('labReturn').onclick = () => {
              this.lab.updateConfig(this.labEditing, this.config);
              this.labEditing = null;
              this.openLab();
            };
          }
        };
      });
    });

    const done = exp.configs.filter(c => c.results && c.results.agg);
    if (done.length >= 1) {
      const rows = done.map(c => {
        const a = c.results.agg;
        const wr = Math.round(a.winsA / a.runs * 100);
        return '<tr><td>' + c.name + '</td><td>' + a.runs + '</td>' +
          '<td><b style="color:var(--accent)">' + wr + '%</b></td>' +
          '<td><b style="color:var(--accent2)">' + Math.round(a.winsB / a.runs * 100) + '%</b></td>' +
          '<td>' + a.avgDuration.toFixed(1) + 's</td>' +
          '<td>' + a.avgSurvivorsA.toFixed(1) + ' / ' + a.avgSurvivorsB.toFixed(1) + '</td>' +
          '<td>' + Math.round(a.avgDamageA) + ' / ' + Math.round(a.avgDamageB) + '</td>' +
          '<td>' + Math.round(a.avgHealingA) + ' / ' + Math.round(a.avgHealingB) + '</td></tr>';
      }).join('');
      $('labComparison').innerHTML = '<table>' +
        '<tr><th>Config</th><th>Runs</th><th>Azure WR</th><th>Crimson WR</th><th>Avg Duration</th><th>Avg Survivors (A/B)</th><th>Avg Dmg (A/B)</th><th>Avg Heal (A/B)</th></tr>' +
        rows + '</table>' +
        '<div class="dim small" style="margin-top:8px">Seeds are deterministic per config+run index, so config differences — not luck — drive results. A few runs ≠ proof; treat ≥25 runs as meaningful evidence.</div>';

      const best = done.slice().sort((x, y) =>
        y.results.agg.winsA / y.results.agg.runs - x.results.agg.winsA / x.results.agg.runs)[0];
      if (best.results.lastInsights) {
        $('labInsights').innerHTML = '<h3 style="font-size:12px;color:var(--dim)">LAST BATTLE — ' + best.name.toUpperCase() + '</h3>' +
          best.results.lastInsights.map(i => '<div class="insightItem">' + i.text + '</div>').join('');
      }
    } else {
      $('labComparison').innerHTML = '<div class="dim">Run the experiment to see comparisons.</div>';
    }

    this.renderLabHistory();
  }

  renderMatrix(m) {
    const el = $('labMatrix');
    if (!el) return;
    const ids = m.ids;
    const lookup = key => m.entries[key];
    const cellRate = (a, b) => {
      if (a === b) return null;
      const e = lookup(a + '|' + b) || lookup(b + '|' + a);
      if (!e) return null;
      const n = e.winsA + e.winsB + e.draws || 1;
      return e.a === a ? (e.winsA + e.draws * 0.5) / n : (e.winsB + e.draws * 0.5) / n;
    };
    const head = '<tr><th></th>' + ids.map(id => '<th title="' + UNITS[id].name + '">' + UNITS[id].name.slice(0, 4) + '</th>').join('') + '<th>Score</th></tr>';
    const scores = new Map(matrixScores(m.entries).map(s => [s.id, s]));
    const rows = ids.map(rowId => {
      const cells = ids.map(colId => {
        const r = cellRate(rowId, colId);
        if (r === null) return '<td class="mCell" style="background:transparent"></td>';
        const g = Math.round(120 + r * 100), rb = Math.round(210 - r * 150);
        return '<td class="mCell" style="background:rgba(' + rb + ',' + g + ',90,0.45)" title="' +
          UNITS[rowId].name + ' vs ' + UNITS[colId].name + ': ' + Math.round(r * 100) + '%">' + Math.round(r * 100) + '</td>';
      }).join('');
      const s = scores.get(rowId);
      return '<tr><th style="text-align:left">' + UNITS[rowId].name + '</th>' + cells +
        '<td><b>' + Math.round(s.score * 100) + '</b></td></tr>';
    }).join('');
    const ranking = matrixScores(m.entries).slice(0, 5).map((s, i) =>
      (i + 1) + '. ' + s.name + ' \u2014 ' + Math.round(s.score * 100) + '% avg win rate').join(' \u00b7 ');
    el.innerHTML =
      '<h3 style="font-size:12px;color:var(--dim)">MATCHUP MATRIX \u2014 1v1 DUEL WIN RATES (' + m.runs + ' runs each, Training Grounds)</h3>' +
      '<div style="overflow-x:auto"><table>' + head + rows + '</table></div>' +
      '<div class="small" style="margin-top:6px"><b>Overall 1v1 ranking:</b> ' + ranking + '</div>' +
      '<div class="dim small">1v1 strength \u2260 army value \u2014 support units score low here but win real battles. Use this to find hard counters, not to pick a "best unit".</div>';
  }

  compSummary(units) {
    const counts = {};
    for (const u of units) {
      const def = resolveDef(u.type, u.upgrade);
      counts[def.name] = (counts[def.name] || 0) + 1;
    }
    return Object.entries(counts).map(pair => pair[1] + '× ' + pair[0]).join(', ') || 'empty';
  }

  renderLabHistory() {
    const list = $('labHistoryList');
    list.innerHTML = '';
    for (const exp of SaveService.listExperiments()) {
      const li = document.createElement('li');
      const nameSpan = document.createElement('span');
      nameSpan.textContent = exp.name;
      const meta = document.createElement('span');
      meta.className = 'expMeta';
      meta.textContent = new Date(exp.created).toLocaleString() + ' · ' + exp.configs.length + ' configs';
      li.appendChild(nameSpan);
      li.appendChild(meta);
      li.onclick = () => { this.lab.loadExperiment(exp); this.renderLab(); };
      li.oncontextmenu = e => {
        e.preventDefault();
        SaveService.deleteExperiment(exp.id);
        this.renderLab();
      };
      list.appendChild(li);
    }
  }

  // ================= misc UI =================
  sendToLab() {
    const exp = this.lab.experiment;
    if (!exp) {
      this.lab.newExperiment(this.config, 'Experiment ' + new Date().toLocaleDateString());
    } else {
      const copy = this.lab.duplicateConfig(exp.configs[0].id, 'Variant from battle');
      if (copy) this.lab.updateConfig(copy.id, this.config, copy.name);
    }
    this.openLab();
    this.toast('Config added to the experiment. Run it against the baseline!');
  }

  rebuildPreview() {
    const cfg = cloneConfig(this.config);
    cfg.collectEvents = false;
    this.previewSim = new BattleSim(cfg);
    this.selectedUnit = null;
  }

  showTypeInfo() {
    const box = $('infoPanel');
    if (!this.selectedType) {
      box.innerHTML = 'Select a unit from the palette, then click your half of the field to place it.<br><br><span class="small">Drag to move · Right-click to remove · Alt-click to duplicate.</span>';
      return;
    }
    const def = resolveDef(this.selectedType, this.placingUpgrade);
    const base = UNITS[this.selectedType];
    const mast = this.progression.masteryTier(this.selectedType);
    let upgradesHtml = '';
    if (base.upgrades && base.upgrades.length) {
      upgradesHtml = '<div style="margin-top:8px"><b class="small">Upgrades (pick one):</b><br>' +
        '<label class="small"><input type="radio" name="upg" value=""' + (!this.placingUpgrade ? ' checked' : '') + '> None</label><br>' +
        base.upgrades.map(u => {
          const unlocked = this.mode === 'sandbox' || this.progression.profile.level >= u.reqLevel;
          return '<label class="small" title="' + u.desc + '"><input type="radio" name="upg" value="' + u.id + '"' +
            (this.placingUpgrade === u.id ? ' checked' : '') + (unlocked ? '' : ' disabled') + '> ' + u.name +
            (unlocked ? '' : ' (Lv ' + u.reqLevel + ')') + '</label>';
        }).join('') + '</div>';
    }
    const fac = FACTIONS[def.faction];
    box.innerHTML =
      '<b style="color:' + def.color + '">' + def.name + '</b> ' +
      '<span class="small" style="color:' + CATEGORIES[def.category].color + '">' + CATEGORIES[def.category].name + '</span>' +
      (fac ? ' <span class="badge" style="background:' + fac.color + ';color:#222">' + fac.name + '</span>' : '') +
      '<div class="small dim" style="margin:4px 0">' + def.desc + '</div>' +
      '<div class="statLine"><span>Cost</span><b style="color:var(--gold)">' + def.cost + '</b></div>' +
      '<div class="statLine"><span>HP</span><b>' + def.hp + '</b></div>' +
      '<div class="statLine"><span>Speed</span><b>' + def.speed + '</b></div>' +
      '<div class="statLine"><span>Attack</span><b>' + def.attack.damage + ' dmg / ' + def.attack.cooldown + 's · ' + def.attack.type + '</b></div>' +
      '<div class="statLine"><span>Range</span><b>' + def.attack.range + '</b></div>' +
      '<div class="statLine"><span>Ability</span><b>' + def.ability.name + '</b></div>' +
      '<div class="small dim">' + def.ability.desc + '</div>' +
      '<div class="small" style="margin-top:6px">Mastery: <b>' + mast.name + '</b> (' + this.progression.masteryOf(def.id) + ' battles fielded)</div>' +
      upgradesHtml;
    box.querySelectorAll('input[name="upg"]').forEach(r => {
      r.onchange = () => {
        this.placingUpgrade = r.value || null;
        this.showTypeInfo();
      };
    });
  }

  showPlacedInfo(entry) {
    const def = resolveDef(entry.type, entry.upgrade);
    const box = $('infoPanel');
    const upgLine = def.upgrade
      ? '<div class="small" style="margin-top:6px;color:var(--gold)">Upgrade: ' + UPGRADES[def.upgrade].name + '</div>' : '';
    box.innerHTML =
      '<b style="color:' + def.color + '">' + def.name + '</b> <span class="dim small">(Team ' + (entry.team === 'A' ? 'Azure' : 'Crimson') + ')</span>' +
      '<div class="small dim" style="margin:4px 0">' + def.desc + '</div>' +
      '<div class="statLine"><span>HP</span><b>' + def.hp + '</b></div>' +
      '<div class="statLine"><span>Speed</span><b>' + def.speed + '</b></div>' +
      '<div class="statLine"><span>Ability</span><b>' + def.ability.name + '</b></div>' +
      '<div class="small dim">' + def.ability.desc + '</div>' +
      upgLine +
      '<div class="row">' +
      '<button id="ipDelete" class="small">🗑 Remove</button>' +
      '<button id="ipDup" class="small">⧉ Duplicate</button></div>';
    $('ipDelete').onclick = () => this.removeUnit(entry);
    $('ipDup').onclick = () => {
      if (!this.canAfford(entry.team, def.cost)) { this.toast('Not enough budget to duplicate.'); return; }
      this.config.teams[entry.team].units.push({ type: entry.type, x: entry.x + 30, y: entry.y + 30, upgrade: entry.upgrade });
      this.rebuildPreview();
      this.refreshBudgetUI();
      this.audio.place();
    };
  }

  refreshBudgetUI() {
    const spendA = this.spentBy('A'), spendB = this.spentBy('B');
    $('budgetA').textContent = this.config.unrestricted ? spendA + ' (∞)' : spendA + '/' + this.config.budgets.A;
    $('budgetB').textContent = this.config.unrestricted ? spendB + ' (∞)' : spendB + '/' + this.config.budgets.B;
    $('unitCount').textContent = (this.config.teams.A.units.length + this.config.teams.B.units.length) + ' units';
    const maxA = this.config.unrestricted ? Math.max(1000, spendA) : this.config.budgets.A;
    const frac = Math.min(1, spendA / maxA);
    $('budgetFill').style.width = (frac * 100) + '%';
    $('budgetFill').style.background = frac > 0.95 ? 'var(--accent2)' : 'var(--accent)';
    $('spentText').textContent = 'Azure budget: ' + spendA + (this.config.unrestricted ? ' (unrestricted)' : ' / ' + this.config.budgets.A);
    if (this.phase === 'setup' && this.mode === 'sandbox') this.saveAutosave();
  }

  refreshAll() {
    this.refreshBudgetUI();
    this.buildPalette();
    this.showTypeInfo();
  }

  refreshConfigList() {
    const sel = $('configList');
    sel.innerHTML = '';
    const all = SaveService.listConfigs();
    for (const name of Object.keys(all)) {
      const o = document.createElement('option');
      o.value = name;
      o.textContent = name;
      sel.appendChild(o);
    }
  }

  updateProgressionUI() {
    const p = this.progression.profile;
    $('profileLevel').textContent = 'Lv ' + p.level;
    const need = 100 + (p.level - 1) * 150;
    $('xpFill').style.width = Math.min(100, p.xp / need * 100) + '%';
    const ach = $('achList');
    ach.innerHTML = '';
    for (const a of ACHIEVEMENTS) {
      const li = document.createElement('li');
      li.className = 'small';
      li.style.color = p.achievements.includes(a.id) ? 'var(--good)' : 'var(--dim)';
      li.textContent = (p.achievements.includes(a.id) ? '✔ ' : '· ') + a.name + ' — ' + a.desc;
      ach.appendChild(li);
    }
  }

  promptModal(title, initial) {
    const init = initial || '';
    return new Promise(resolve => {
      $('modalTitle').textContent = title;
      $('modalInput').value = init;
      $('modal').classList.remove('hidden');
      $('modalInput').focus();
      const done = val => {
        $('modal').classList.add('hidden');
        $('modalOk').onclick = null;
        $('modalCancel').onclick = null;
        resolve(val);
      };
      $('modalOk').onclick = () => done($('modalInput').value.trim() || null);
      $('modalCancel').onclick = () => done(null);
      $('modalInput').onkeydown = e => {
        if (e.key === 'Enter') done($('modalInput').value.trim() || null);
        if (e.key === 'Escape') done(null);
      };
    });
  }

  toast(msg) {
    const t = $('toast');
    t.textContent = msg;
    t.classList.remove('hidden');
    clearTimeout(this._toastTimer);
    this._toastTimer = setTimeout(() => t.classList.add('hidden'), 2600);
  }
}
