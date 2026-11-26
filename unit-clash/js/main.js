import { GameController } from './ui.js';

const game = new GameController();
game.init();

// Expose for console-driven debugging only.
window.__UNIT_CLASH = game;
