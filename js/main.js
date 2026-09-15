"use strict";
/* Bootstrap: wire the canvas up and open the title screen. */
window.addEventListener("load", () => {
  const game = new TC.Game(document.getElementById("cv"));
  window.TCGAME = game;                 // handy for debugging from the console
  game.title();
  // The first gesture anywhere unlocks WebAudio on iOS/Safari.
  const unlock = () => { TC.audio.unlock(); window.removeEventListener("pointerdown", unlock); };
  window.addEventListener("pointerdown", unlock);
});
