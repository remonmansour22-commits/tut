// Statistics tracking + aggregation + insight generation.
// The tracker is written by the simulation each tick; insights are derived
// ONLY from real tracked numbers.

export class StatsTracker {
  constructor(sim) {
    this.sim = sim;
    this.team = { A: emptyTeamStats(), B: emptyTeamStats() };
    this.units = new Map(); // unitId -> record
    this.timeline = []; // {t, event:'death', team}
  }
  register(unit) {
    this.units.set(unit.uid, {
      uid: unit.uid, unitId: unit.def.id, team: unit.team, name: unit.def.name,
      cost: unit.def.cost, category: unit.def.category,
      spawnedAt: 0, diedAt: null, damageDealt: 0, damageTaken: 0,
      healing: 0, healingRecv: 0, kills: 0, abilityUses: 0, shielded: 0
    });
  }
  rec(uid) { return this.units.get(uid); }
  addDamage(attacker, target, amount) {
    if (attacker && this.units.has(attacker.uid)) this.units.get(attacker.uid).damageDealt += amount;
    if (this.units.has(target.uid)) this.units.get(target.uid).damageTaken += amount;
    this.team[attacker ? attacker.team : target.team === 'A' ? 'B' : 'A'].damageDealt += amount;
    this.team[target.team].damageTaken += amount;
  }
  addHeal(source, target, amount) {
    if (source && this.units.has(source.uid)) this.units.get(source.uid).healing += amount;
    if (this.units.has(target.uid)) this.units.get(target.uid).healingRecv += amount;
    if (source) this.team[source.team].healing += amount;
    if (target && target.team) this.team[target.team].healingRecv += amount;
  }
  addKill(killer, victim) {
    if (killer && this.units.has(killer.uid)) this.units.get(killer.uid).kills++;
    this.team[killer ? killer.team : 'A'].kills++;
    const vr = this.units.get(victim.uid);
    if (vr) { vr.diedAt = this.sim.t; }
    this.team[victim.team].lost++;
    this.timeline.push({ t: this.sim.t, type: 'death', team: victim.team, unitId: victim.def.id });
  }
  addAbility(unit) {
    if (this.units.has(unit.uid)) this.units.get(unit.uid).abilityUses++;
  }
  addDeviceDamage(attacker, device, amount) {
    const t = attacker && attacker.team ? attacker.team : (device.team === 'A' ? 'B' : 'A');
    this.team[t].deviceDamage += amount;
    if (attacker && this.units.has(attacker.uid)) this.units.get(attacker.uid).damageDealt += amount;
  }
  snapshot() {
    const team = JSON.parse(JSON.stringify(this.team));
    team.A.survivors = this.sim.aliveOf('A');
    team.B.survivors = this.sim.aliveOf('B');
    return {
      duration: this.sim.t,
      outcome: this.sim.outcome,
      team,
      units: [...this.units.values()].map(r => ({ ...r })),
      timeline: this.timeline.slice()
    };
  }
}

function emptyTeamStats() {
  return { damageDealt: 0, damageTaken: 0, healing: 0, healingRecv: 0, kills: 0, lost: 0, deviceDamage: 0 };
}

// Aggregate several battle snapshots for one configuration (Battle Lab).
export function aggregate(snapshots) {
  const n = snapshots.length || 1;
  const agg = {
    runs: n,
    winsA: 0, winsB: 0, draws: 0,
    avgDuration: 0, avgSurvivorsA: 0, avgSurvivorsB: 0,
    avgDamageA: 0, avgDamageB: 0,
    avgHealingA: 0, avgHealingB: 0,
    avgHealRecvA: 0, avgHealRecvB: 0,
    avgLostA: 0, avgLostB: 0,
    avgDeviceDamageA: 0, avgDeviceDamageB: 0,
    unitPerf: new Map()
  };
  for (const s of snapshots) {
    if (s.outcome.winner === 'A') agg.winsA++;
    else if (s.outcome.winner === 'B') agg.winsB++;
    else agg.draws++;
    agg.avgDuration += s.duration;
    agg.avgSurvivorsA += s.team.A.survivors; agg.avgSurvivorsB += s.team.B.survivors;
    agg.avgDamageA += s.team.A.damageDealt; agg.avgDamageB += s.team.B.damageDealt;
    agg.avgHealingA += s.team.A.healing; agg.avgHealingB += s.team.B.healing;
    agg.avgHealRecvA += s.team.A.healingRecv || 0; agg.avgHealRecvB += s.team.B.healingRecv || 0;
    agg.avgLostA += s.team.A.lost; agg.avgLostB += s.team.B.lost;
    agg.avgDeviceDamageA += s.team.A.deviceDamage || 0; agg.avgDeviceDamageB += s.team.B.deviceDamage || 0;
    for (const u of s.units) {
      const key = u.team + ':' + u.unitId;
      let rec = agg.unitPerf.get(key);
      if (!rec) { rec = { team: u.team, unitId: u.unitId, name: u.name, runs: 0, avgDmg: 0, avgHeal: 0, avgKills: 0, avgLife: 0, survived: 0 }; agg.unitPerf.set(key, rec); }
      rec.runs++;
      rec.avgDmg += u.damageDealt; rec.avgHeal += u.healing; rec.avgKills += u.kills;
      rec.avgLife += (u.diedAt != null ? u.diedAt : s.duration);
      if (u.diedAt == null) rec.survived++;
    }
  }
  for (const rec of agg.unitPerf.values()) {
    rec.avgDmg /= rec.runs; rec.avgHeal /= rec.runs; rec.avgKills /= rec.runs; rec.avgLife /= rec.runs;
  }
  agg.unitPerf = [...agg.unitPerf.values()];
  agg.avgDuration /= n; agg.avgSurvivorsA /= n; agg.avgSurvivorsB /= n;
  agg.avgDamageA /= n; agg.avgDamageB /= n;
  agg.avgHealingA /= n; agg.avgHealingB /= n;
  agg.avgHealRecvA /= n; agg.avgHealRecvB /= n;
  agg.avgLostA /= n; agg.avgLostB /= n;
  agg.avgDeviceDamageA /= n; agg.avgDeviceDamageB /= n;
  return agg;
}

// Insight generation — every insight is grounded in tracked statistics.
export function generateInsights(snapshot) {
  const out = [];
  const { team, units, duration } = snapshot;
  const deaths = units.filter(u => u.diedAt != null);

  const firstDeaths = deaths.slice().sort((a, b) => a.diedAt - b.diedAt);
  const firstThree = firstDeaths.slice(0, 3);
  if (firstThree.length >= 2 && firstThree.every(u => u.team === firstThree[0].team)) {
    const losing = firstThree[0].team;
    const cats = firstThree.map(u => u.category);
    if (cats.some(c => c === 'frontline' || c === 'heavy')) {
      out.push({
        team: losing, icon: 'shield',
        text: `The ${teamName(losing)} frontline collapsed early (${fmt(firstThree[0].diedAt)}s) — its heavier units fell first, leaving supports exposed.`
      });
    }
  }

  for (const t of ['A', 'B']) {
    const heals = units.filter(u => u.team === t && (u.unitId === 'medic' || u.unitId === 'artificer'));
    const totalHeal = heals.reduce((s, u) => s + u.healing, 0);
    if (heals.length === 0 && team[t].lost > 0) {
      out.push({ team: t, icon: 'cross', text: `${teamName(t)} fielded no sustain units and lost ${team[t].lost}. A Medic or Artificer may have changed the outcome.` });
    } else if (heals.length && totalHeal < 40 && team[t].lost > 0) {
      out.push({ team: t, icon: 'cross', text: `${teamName(t)} brought sustain but only generated ${Math.round(totalHeal)} healing — the healers may have been out of position or killed early.` });
    }
  }

  for (const t of ['A', 'B']) {
    const back = deaths.filter(u => u.team === t && (u.category === 'ranged' || u.category === 'support'));
    const frontAlive = units.filter(u => u.team === t && u.diedAt == null && (u.category === 'frontline' || u.category === 'heavy'));
    if (back.length >= 2 && frontAlive.length === 0 && team[t === 'A' ? 'B' : 'A'].kills > 0) {
      out.push({ team: t, icon: 'bow', text: `${teamName(t)}'s ranged units died while no frontline remained — they had no protection screen.` });
    }
  }

  let mvp = null;
  for (const u of units) {
    const score = u.damageDealt + u.healing * 1.2 + u.kills * 30;
    if (!mvp || score > mvp._score) { mvp = { ...u, _score: score }; }
  }
  if (mvp && mvp._score > 60) {
    out.push({
      team: mvp.team, icon: 'star',
      text: `MVP: ${mvp.name} (${teamName(mvp.team)}) — ${Math.round(mvp.damageDealt)} damage, ${mvp.kills} kills${mvp.healing > 5 ? `, ${Math.round(mvp.healing)} healing` : ''}.`
    });
  }

  for (const t of ['A', 'B']) {
    const deployed = units.filter(u => u.team === t);
    const costByCat = {};
    for (const u of deployed) costByCat[u.category] = (costByCat[u.category] || 0) + u.cost;
    const total = deployed.reduce((s, u) => s + u.cost, 0);
    for (const [cat, c] of Object.entries(costByCat)) {
      if (total > 0 && c / total > 0.6 && deployed.length >= 3 && team[t].lost >= deployed.length * 0.6) {
        out.push({ team: t, icon: 'coins', text: `${teamName(t)} spent ${Math.round(c / total * 100)}% of its budget on ${cat} units and lost most of the army — a heavily one-role army can collapse to a hard counter.` });
        break;
      }
    }
  }

  for (const t of ['A', 'B']) {
    const dd = team[t].deviceDamage || 0;
    if (dd >= 150) {
      out.push({ team: t, icon: 'coins', text: `${teamName(t)}'s devices dealt ${Math.round(dd)} damage \u2014 that Engineer investment more than paid for itself.` });
    }
  }

  if (snapshot.outcome.winner !== 'draw') {
    const w = team[snapshot.outcome.winner];
    const l = team[snapshot.outcome.winner === 'A' ? 'B' : 'A'];
    const wSurv = w.survivors, lSurv = l.survivors;
    if (wSurv <= 2 && lSurv === 0) {
      out.push({ team: snapshot.outcome.winner, icon: 'flame', text: `A razor-close victory: ${teamName(snapshot.outcome.winner)} won with only ${wSurv} unit(s) standing after ${fmt(duration)}s.` });
    }
  } else {
    out.push({ team: null, icon: 'scale', text: `Stalemate after ${fmt(duration)}s — neither army could close it out. More damage or sustain may tip it.` });
  }

  return out;
}

function teamName(t) { return t === 'A' ? 'Team Azure' : 'Team Crimson'; }
function fmt(x) { return (Math.round(x * 10) / 10).toFixed(1); }
