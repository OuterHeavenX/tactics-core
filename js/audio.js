"use strict";
/* ============================================================================
   TACTICS CORE — AUDIO
   Everything is synthesised with WebAudio at runtime: no asset downloads, so
   the game still boots instantly from a cold cache on a phone.
   ========================================================================== */
var TC = window.TC || (window.TC = {});   /* var, not const: these are classic scripts sharing one global scope */

class AudioKit {
  constructor() {
    this.ctx = null;
    this.enabled = localStorage.getItem("tc.sound") !== "0";
    this.musicOn = localStorage.getItem("tc.music") !== "0";
    this.musicTimer = null;
    this.step = 0;
  }
  /* Browsers only allow audio after a gesture, so this is called from input. */
  unlock() {
    if (this.ctx) { if (this.ctx.state === "suspended") this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    this.ctx = new AC();
    this.master = this.ctx.createGain();
    this.master.gain.value = 0.32;
    this.master.connect(this.ctx.destination);
    this.musicGain = this.ctx.createGain();
    this.musicGain.gain.value = 0.16;
    this.musicGain.connect(this.master);
    if (this.musicOn) this.startMusic();
  }
  setSound(on) { this.enabled = on; localStorage.setItem("tc.sound", on ? "1" : "0"); }
  setMusic(on) {
    this.musicOn = on; localStorage.setItem("tc.music", on ? "1" : "0");
    if (on) this.startMusic(); else this.stopMusic();
  }

  tone(freq, dur, type, gain, dest, slide) {
    if (!this.ctx || !this.enabled) return;
    const t = this.ctx.currentTime;
    const o = this.ctx.createOscillator(), g = this.ctx.createGain();
    o.type = type || "square";
    o.frequency.setValueAtTime(freq, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(30, slide), t + dur);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(gain || 0.25, t + 0.012);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(dest || this.master);
    o.start(t); o.stop(t + dur + 0.02);
  }
  noise(dur, gain, filterHz) {
    if (!this.ctx || !this.enabled) return;
    const t = this.ctx.currentTime;
    const n = Math.floor(this.ctx.sampleRate * dur);
    const buf = this.ctx.createBuffer(1, n, this.ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / n);
    const src = this.ctx.createBufferSource(); src.buffer = buf;
    const f = this.ctx.createBiquadFilter(); f.type = "lowpass"; f.frequency.value = filterHz || 1400;
    const g = this.ctx.createGain(); g.gain.value = gain || 0.3;
    src.connect(f); f.connect(g); g.connect(this.master);
    src.start(t);
  }

  play(name) {
    if (!this.ctx || !this.enabled) return;
    switch (name) {
      case "select":  this.tone(680, .06, "square", .18); break;
      case "cancel":  this.tone(300, .08, "square", .15); break;
      case "move":    this.tone(420, .05, "triangle", .14); break;
      case "hit":     this.noise(.16, .34, 2200); this.tone(160, .12, "sawtooth", .2, null, 70); break;
      case "crit":    this.noise(.22, .45, 3600); this.tone(240, .18, "sawtooth", .28, null, 60);
                      setTimeout(() => this.tone(900, .1, "square", .2), 60); break;
      case "miss":    this.tone(520, .1, "sine", .14, null, 300); break;
      case "magic":   this.tone(520, .28, "sine", .2, null, 1500);
                      setTimeout(() => this.tone(780, .22, "sine", .16, null, 1900), 70); break;
      case "heal":    this.tone(660, .18, "sine", .2); setTimeout(() => this.tone(880, .22, "sine", .18), 90);
                      setTimeout(() => this.tone(1180, .26, "sine", .14), 180); break;
      case "ko":      this.tone(220, .5, "sawtooth", .26, null, 60); this.noise(.4, .3, 900); break;
      case "levelup": [523, 659, 784, 1046].forEach((f, i) => setTimeout(() => this.tone(f, .2, "square", .2), i * 85)); break;
      case "victory": [523, 659, 784, 1046, 1318].forEach((f, i) => setTimeout(() => this.tone(f, .34, "triangle", .24), i * 130)); break;
      case "defeat":  [392, 349, 311, 233].forEach((f, i) => setTimeout(() => this.tone(f, .5, "sawtooth", .2), i * 190)); break;
      case "turn":    this.tone(880, .07, "sine", .13); break;
      case "boss":    this.tone(90, .8, "sawtooth", .3); this.noise(.8, .2, 400); break;
    }
  }

  /* Eight-bar minor-key ostinato. Cheap, loops forever, stays out of the way. */
  startMusic() {
    if (!this.ctx || this.musicTimer) return;
    const scale = [220, 246.9, 261.6, 293.7, 329.6, 349.2, 392, 440];
    const bass = [110, 110, 146.8, 130.8];
    this.step = 0;
    this.musicTimer = setInterval(() => {
      if (!this.musicOn || !this.ctx) return;
      const s = this.step++;
      if (s % 4 === 0) this.tone(bass[(s / 4) % 4 | 0], .55, "triangle", .3, this.musicGain);
      if (s % 2 === 0) {
        const n = scale[(s * 3 + Math.floor(s / 8)) % scale.length];
        this.tone(n * 2, .26, "sine", .16, this.musicGain);
      }
      if (s % 8 === 6) this.tone(scale[(s / 2) % scale.length] * 4, .2, "sine", .07, this.musicGain);
    }, 250);
  }
  stopMusic() { if (this.musicTimer) { clearInterval(this.musicTimer); this.musicTimer = null; } }
}
TC.audio = new AudioKit();
