// localStorage persistence with graceful degradation (private mode, etc.)
const PREFIX = 'unitclash.v1.';

function get(key, fallback) {
  try {
    const raw = localStorage.getItem(PREFIX + key);
    if (raw == null) return fallback;
    return JSON.parse(raw);
  } catch { return fallback; }
}
function set(key, value) {
  try { localStorage.setItem(PREFIX + key, JSON.stringify(value)); return true; }
  catch { return false; }
}

export const SaveService = {
  // battle configurations
  listConfigs() { return get('configs', {}); },
  saveConfig(name, config, notes = '') {
    const all = this.listConfigs();
    all[name] = { name, config, notes, savedAt: Date.now() };
    set('configs', all);
  },
  deleteConfig(name) {
    const all = this.listConfigs();
    delete all[name];
    set('configs', all);
  },
  // autosave of last sandbox setup
  getAutosave() { return get('autosave', null); },
  setAutosave(config) { set('autosave', config); },
  // experiments (battle lab history)
  listExperiments() { return get('experiments', []); },
  saveExperiment(exp) {
    const all = this.listExperiments();
    const i = all.findIndex(e => e.id === exp.id);
    if (i >= 0) all[i] = exp; else all.unshift(exp);
    if (all.length > 60) all.length = 60;
    set('experiments', all);
  },
  deleteExperiment(id) {
    set('experiments', this.listExperiments().filter(e => e.id !== id));
  },
  // progression
  getProfile() {
    return get('profile', { xp: 0, level: 1, mastery: {}, achievements: [], campaignProgress: 0 });
  },
  setProfile(p) { set('profile', p); },
  // settings
  getSettings() { return get('settings', { muted: false, alwaysBars: false }); },
  setSettings(s) { set('settings', s); }
};
