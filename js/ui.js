"use strict";
/* ============================================================================
   TACTICS CORE — GAME CONTROLLER
   Owns the screen flow (title -> briefing -> battle -> results), the player's
   action menu, targeting previews and input. The rules live in battle.js;
   this file only ever asks it to do things and animates the answer.
   ========================================================================== */
var TC = window.TC || (window.TC = {});   /* var, not const: these are classic scripts sharing one global scope */
const $ = id => document.getElementById(id);
const el = (tag, cls, html) => { const n = document.createElement(tag); if (cls) n.className = cls; if (html != null) n.innerHTML = html; return n; };

const SAVE_KEY = "tc.save.v2";

class Game {
  constructor(canvas) {
    this.r = new TC.Renderer(canvas);
    this.battle = null;
    this.mode = "idle";          // idle | move | target | enemy | busy | over
    this.pending = null;         // { ability } or { item }
    this.hover = null;
    this.inspecting = null;
    this.busy = false;
    this.logLines = [];
    this.progress = this.load();
    this.bindInput();
    this.last = performance.now();
    requestAnimationFrame(t => this.frame(t));
  }

  /* ------------------------------------------------------------- saving */
  load() {
    try {
      const raw = localStorage.getItem(SAVE_KEY);
      if (raw) return JSON.parse(raw);
    } catch (e) { /* corrupt save: start fresh rather than crash */ }
    return null;
  }
  save() {
    if (!this.progress) return;
    try { localStorage.setItem(SAVE_KEY, JSON.stringify(this.progress)); } catch (e) {}
  }
  newProgress(difficulty) {
    return { chapter: 0, difficulty: difficulty || "normal", wins: 0,
             party: TC.PARTY.map(p => ({ name: p.name, job: p.job, level: 1, xp: 0, jp: 0, learned: [] })) };
  }
  get difficulty() { return TC.DIFFICULTY[(this.progress && this.progress.difficulty) || "normal"]; }

  /* ------------------------------------------------------------ screens */
  modal(html, on) {
    $("sheet").innerHTML = html;
    $("modal").classList.toggle("on", on !== false);
  }
  closeModal() { $("modal").classList.remove("on"); }

  title() {
    this.mode = "over";
    const has = !!this.progress && this.progress.chapter > 0;
    this.modal(`
      <h1>Tactics Core</h1>
      <p>Isometric 2.5D tactics. Charge-time turns, real terrain height, facing-based
      damage and a four-chapter campaign — all in a browser tab.</p>
      <div class="roster">${TC.PARTY.map(p => {
        const j = TC.JOBS[p.job];
        return `<div class="r"><div class="n">${j.icon} ${p.name}</div><div class="j">${p.job}</div><div class="l">${j.blurb}</div></div>`;
      }).join("")}</div>
      <div class="row">
        ${has ? `<button class="abtn primary" data-act="continue">Continue — Chapter ${this.progress.chapter + 1} (${this.difficulty.name})</button>` : ""}
        <button class="abtn" data-act="help">How to Play</button>
      </div>
      <div class="h2" style="margin-top:14px">New campaign</div>
      <div class="row" style="margin-top:6px">
        ${Object.entries(TC.DIFFICULTY).map(([id, d]) =>
          `<button class="abtn ${id === "normal" && !has ? "primary" : ""}" data-act="new" data-diff="${id}" title="${d.blurb}">${d.name}</button>`).join("")}
      </div>
      <p style="margin-top:8px;font-size:11.5px">${Object.values(TC.DIFFICULTY).map(d => `<b>${d.name}</b> — ${d.blurb}`).join(" &nbsp;·&nbsp; ")}</p>`);
    $("sheet").onclick = e => {
      const a = e.target.closest("[data-act]"); if (!a) return;
      TC.audio.unlock(); TC.audio.play("select");
      if (a.dataset.act === "help") return this.help(() => this.title());
      if (a.dataset.act === "new") { this.progress = this.newProgress(a.dataset.diff); this.save(); }
      this.briefing();
    };
  }

  help(back) {
    this.modal(`
      <h2>How to Play</h2>
      <div class="helpgrid">
        <div><b>Turn order</b> — charge time. Each unit builds CT from its Speed; at 100 it acts.
          Doing less leaves you more CT, so waiting gets you back sooner than moving <i>and</i> attacking.</div>
        <div><b>Height is real</b> — attacking from above adds accuracy and damage. Your Jump stat caps
          how big a step you can climb, so terraces and cliffs are walls until you find the ramp.</div>
        <div><b>Facing matters</b> — the arrow under each unit is where it is looking.
          Strike from the side for +25% damage, from behind for <b>+50%</b> and a much better hit chance.</div>
        <div><b>Move and act</b> — you get one move and one action per turn, in either order.
          Move first and you can still undo it, right up until you act.</div>
        <div><b>Terrain</b> — forest grants evasion, rock grants defence, lava burns anything that
          stops on it, and water is impassable.</div>
        <div><b>Controls</b> — <kbd>click/tap</kbd> a tile to move or target,
          <kbd>Q</kbd>/<kbd>E</kbd> rotate the camera, <kbd>+</kbd>/<kbd>−</kbd> zoom,
          <kbd>Space</kbd> wait, <kbd>U</kbd> undo move, <kbd>Esc</kbd> cancel,
          <kbd>Tab</kbd> inspect the next unit. Drag to pan, pinch to zoom.</div>
      </div>
      <div class="row"><button class="abtn primary" data-act="back">Back</button></div>`);
    $("sheet").onclick = e => { if (e.target.closest("[data-act]")) { TC.audio.play("select"); back ? back() : this.closeModal(); } };
  }

  pauseMenu() {
    const snd = TC.audio.enabled ? "on" : "off", mus = TC.audio.musicOn ? "on" : "off";
    this.modal(`
      <h2>Paused</h2>
      <p>${this.battle ? this.battle.chapter.title : "Tactics Core"}</p>
      <div class="row">
        <button class="abtn primary" data-act="resume">Resume</button>
        <button class="abtn" data-act="sound">🔊 Sound: ${snd}</button>
        <button class="abtn" data-act="music">🎵 Music: ${mus}</button>
      </div>
      <div class="row">
        <button class="abtn" data-act="help">How to Play</button>
        <button class="abtn" data-act="fit">Recentre Camera</button>
        ${this.battle ? `<button class="abtn danger" data-act="restart">Restart Battle</button>` : ""}
        <button class="abtn danger" data-act="title">Main Menu</button>
      </div>`);
    $("sheet").onclick = e => {
      const a = e.target.closest("[data-act]"); if (!a) return;
      TC.audio.unlock(); TC.audio.play("select");
      switch (a.dataset.act) {
        case "resume": return this.closeModal();
        case "sound": TC.audio.setSound(!TC.audio.enabled); return this.pauseMenu();
        case "music": TC.audio.setMusic(!TC.audio.musicOn); return this.pauseMenu();
        case "help": return this.help(() => this.pauseMenu());
        case "fit": this.r.fit(); return this.closeModal();
        case "restart": this.closeModal(); return this.startBattle(this.battle.chapter);
        case "title": return this.title();
      }
    };
  }

  briefing() {
    const idx = Math.min(this.progress.chapter, TC.CAMPAIGN.length - 1);
    const ch = TC.CAMPAIGN[idx];
    this.mode = "over";
    this.modal(`
      <h2>${ch.title}</h2>
      <p>${ch.brief}</p>
      <div class="roster">${this.progress.party.map(p => {
        const j = TC.JOBS[p.job];
        return `<div class="r"><div class="n">${j.icon} ${p.name}</div><div class="j">${p.job} · Lv ${p.level}</div><div class="l">${j.blurb}</div></div>`;
      }).join("")}</div>
      <div class="tip">💡 ${ch.tip}</div>
      <div class="row">
        <button class="abtn primary" data-act="go">Begin Battle</button>
        <button class="abtn" data-act="learn">Learn Abilities</button>
        <button class="abtn" data-act="help">How to Play</button>
        <button class="abtn" data-act="title">Main Menu</button>
      </div>`);
    $("sheet").onclick = e => {
      const a = e.target.closest("[data-act]"); if (!a) return;
      TC.audio.unlock(); TC.audio.play("select");
      if (a.dataset.act === "learn") return this.learnScreen();
      if (a.dataset.act === "help") return this.help(() => this.briefing());
      if (a.dataset.act === "title") return this.title();
      this.closeModal();
      this.startBattle(ch);
    };
  }

  startBattle(ch) {
    // A battle can be started from the middle of targeting (menu -> new chapter),
    // so every transient bit of UI state has to be cleared first.
    this.mode = "idle";
    this.pending = null;
    this.hover = null;
    this.inspecting = null;
    this.busy = false;
    this.tapTile = null;
    this.clearOverlays();
    this.hint("");
    $("inspect").style.display = "none";
    this.battle = new TC.Battle(ch, this.progress.party, { levelOffset: this.difficulty.levelOffset });
    this.r.attach(this.battle);
    this.logLines = [];
    $("logbox").innerHTML = "";
    const objective = ch.objective === "boss" ? "Slay the boss" : ch.objective === "protect" ? `Keep ${ch.npc[0]} alive` : "Defeat all enemies";
    $("chapter").innerHTML = `<div class="title">${ch.title.replace(/^Chapter \d+ — /, "")}</div><div class="obj">${objective}</div>`;
    this.log(`<b>${ch.title}</b> — ${objective.toLowerCase()}.`, "s");
    if (ch.boss) TC.audio.play("boss");
    this.enterDeploy();
  }

  /* Before turn one the player may shuffle the party around the deploy zone. */
  enterDeploy() {
    this.mode = "deploy";
    this.deploySel = null;
    this.clearOverlays();
    for (const t of this.battle.deployZone()) this.r.overlays.move.add(TC.KEY(t.x, t.y));
    this.hint("Deployment: tap a unit, then a highlighted tile. Start when ready.");
    this.refresh();
  }
  deployClick(tile, clicked) {
    const b = this.battle;
    if (this.deploySel) {
      if (b.placeUnit(this.deploySel, tile.x, tile.y)) { TC.audio.play("move"); this.deploySel = null; this.r.cursor = tile; }
      else if (clicked && clicked.team === "P" && !clicked.npc) this.deploySel = clicked;
      else { TC.audio.play("cancel"); this.deploySel = null; }
    } else if (clicked && clicked.team === "P" && !clicked.npc) {
      this.deploySel = clicked; TC.audio.play("select");
    }
    this.showInspect(clicked);
    this.hint(this.deploySel ? `Moving ${this.deploySel.name}: tap a highlighted tile (or another unit to swap).`
                             : "Deployment: tap a unit, then a highlighted tile. Start when ready.");
    this.refresh();
  }
  beginBattle() {
    if (this.mode !== "deploy") return;
    this.deploySel = null;
    this.clearOverlays(); this.hint("");
    this.mode = "idle";
    this.advance();
  }

  /* ------------------------------------------------------------ battle */
  advance() {
    if (!this.battle) return;
    if (this.battle.checkEnd()) { this.playEvents(this.battle.drain(), () => this.finish()); return; }
    const u = this.battle.beginTurn();
    const evts = this.battle.drain();
    if (!u) { this.playEvents(evts, () => this.finish()); return; }
    this.playEvents(evts, () => {
      if (this.battle.over) return this.finish();
      this.r.cursor = { x: u.x, y: u.y };
      this.inspecting = u;
      if (this.r.shouldFollow) this.r.focusOn(u.x, u.y);
      this.syncThreat();
      if (u.team === "P" && !u.npc) {
        this.mode = "idle";
        this.turnSnap = this.difficulty.undoTurn ? this.battle.snapshot() : null;
        TC.audio.play("turn");
        this.log(`<span class="p">${u.name}</span>'s turn.`);
        this.refresh();
      } else {
        this.mode = "enemy";
        this.refresh();
        setTimeout(() => this.enemyTurn(u), 320);
      }
    });
  }

  enemyTurn(u) {
    const b = this.battle;
    const step = (fn, ms) => setTimeout(fn, ms);
    TC.runEnemyTurn(b, u, (fn, ms) => {
      this.playEvents(b.drain(), () => step(fn, ms));
    }, () => {
      this.playEvents(b.drain(), () => {
        b.endTurn(u);
        this.playEvents(b.drain(), () => setTimeout(() => this.advance(), 200));
      });
    });
  }

  /* Story mode: put the whole turn back the way it was. */
  rewindTurn() {
    if (this.busy || !this.turnSnap || !this.battle || this.mode === "enemy") return;
    const b = this.battle;
    b.restore(this.turnSnap);
    for (const u of b.units) this.r.unitFx.delete(u.id);
    this.mode = "idle"; this.pending = null;
    this.clearOverlays(); this.hint("");
    TC.audio.play("cancel");
    this.log(`<span class="s">Turn rewound.</span>`);
    b.drain();
    this.syncThreat();
    this.refresh();
  }

  /* Tiles that a charging enemy spell will hit are shown in red. */
  syncThreat() {
    const o = this.r.overlays; o.threat.clear();
    for (const p of this.battle.pending) {
      const caster = this.battle.units[p.casterId];
      if (!caster) continue;
      for (const t of TC.footprint(this.battle.grid, caster, TC.ABILITIES[p.abilityId], p.tx, p.ty)) o.threat.add(TC.KEY(t.x, t.y));
    }
    this.r.casters = new Set(this.battle.pending.map(p => p.casterId));
  }

  endTurn() {
    if (this.busy || this.mode === "enemy" || !this.battle || !this.battle.active) return;
    const u = this.battle.active;
    this.battle.endTurn(u);
    this.clearOverlays();
    this.playEvents(this.battle.drain(), () => setTimeout(() => this.advance(), 160));
  }

  finish() {
    this.mode = "over";
    this.clearOverlays();
    const win = this.battle.over === "victory";
    TC.audio.play(win ? "victory" : "defeat");
    const ch = this.battle.chapter;
    const levelups = [];
    if (win) {
      const fighters = this.battle.living("P").filter(u => !u.npc).length;
      const share = Math.round(ch.xp / Math.max(1, fighters));
      for (const u of this.battle.units.filter(u => u.team === "P" && !u.npc)) {
        const before = u.level;
        u.gainXp(u.alive ? share : Math.round(share * 0.4), this.battle);
        if (u.level > before) levelups.push(`${u.name} → Lv ${u.level}`);
      }
      // Carry levels forward; the fallen are patched up between chapters.
      this.progress.party = this.battle.units.filter(u => u.team === "P" && !u.npc)
        .map(u => ({ name: u.name, job: u.job, level: u.level, xp: u.xp, jp: u.jp, learned: u.learned.slice() }));
      this.progress.chapter = Math.min(TC.CAMPAIGN.length, TC.CAMPAIGN.indexOf(ch) + 1);
      this.progress.wins++;
      this.save();
    }
    const done = win && this.progress.chapter >= TC.CAMPAIGN.length;
    this.modal(`
      <h1 style="color:${win ? "var(--gold)" : "var(--red)"}">${done ? "Campaign Clear" : win ? "Victory" : "Defeat"}</h1>
      <p>${done ? "The Necrohol is silent. Your company walks out of it alive."
           : win ? `The field is yours. ${ch.xp} XP shared across the company.`
           : "Your company is broken. Regroup and try the battle again."}</p>
      ${levelups.length ? `<div class="tip">⬆ ${levelups.join(" · ")}</div>` : ""}
      <div class="roster">${this.battle.units.filter(u => u.team === "P" && !u.npc).map(u =>
        `<div class="r"><div class="n">${u.icon} ${u.name}</div><div class="j">${u.job} · Lv ${u.level}</div>
         <div class="l">${u.alive ? `${u.hp}/${u.maxHp} HP` : "<span style='color:var(--red)'>fallen</span>"} · ${u.xp}/${u.xpToNext} XP · ${u.jp} JP</div></div>`).join("")}</div>
      <div class="row">
        ${done ? `<button class="abtn primary" data-act="title">Main Menu</button>`
               : win ? `<button class="abtn primary" data-act="learn">Learn Abilities</button>`
                     : `<button class="abtn primary" data-act="retry">Retry Battle</button>`}
        <button class="abtn" data-act="title">Main Menu</button>
      </div>`);
    $("sheet").onclick = e => {
      const a = e.target.closest("[data-act]"); if (!a) return;
      TC.audio.play("select");
      if (a.dataset.act === "title") return this.title();
      if (a.dataset.act === "retry") { this.closeModal(); return this.startBattle(ch); }
      if (a.dataset.act === "learn") return this.learnScreen();
      this.briefing();
    };
  }

  /* Spend JP between chapters. Works on the saved party, so it is safe to
     leave and come back to from the title screen. */
  learnScreen() {
    this.mode = "over";
    const party = this.progress.party;
    const cards = party.map((p, i) => {
      const job = TC.JOBS[p.job];
      const known = new Set((job.starting || job.abilities).concat(p.learned || []));
      const options = job.abilities.filter(id => !known.has(id) && TC.ABILITIES[id].jp);
      const rows = options.length ? options.map(id => {
        const a = TC.ABILITIES[id], can = (p.jp || 0) >= a.jp;
        return `<div class="learn-row">
          <div><b>${a.name}</b> <span class="cost">${a.jp} JP${a.mp ? ` · ${a.mp} MP` : ""}${a.charge ? " · charges" : ""}</span><div class="ldesc">${a.desc}</div></div>
          <button class="abtn ${can ? "primary" : ""}" data-act="learn" data-i="${i}" data-id="${id}" ${can ? "" : "disabled"}>Learn</button>
        </div>`;
      }).join("") : `<div class="ldesc">Everything learned.</div>`;
      const knownList = [...known].map(id => TC.ABILITIES[id].name).join(", ");
      return `<div class="r learn-card">
        <div class="n" style="color:${job.color}">${job.icon} ${p.name} <span class="cost">${p.jp || 0} JP</span></div>
        <div class="j">${p.job} · Lv ${p.level}</div>
        <div class="ldesc">Knows: ${knownList}</div>
        ${rows}
      </div>`;
    }).join("");
    this.modal(`
      <h2>Learn Abilities</h2>
      <p>JP is earned alongside XP. Anything you don't buy now is still there next time.</p>
      <div class="roster learn">${cards}</div>
      <div class="row"><button class="abtn primary" data-act="next">Next Chapter</button>
      <button class="abtn" data-act="title">Main Menu</button></div>`);
    $("sheet").onclick = e => {
      const a = e.target.closest("[data-act]"); if (!a) return;
      TC.audio.play("select");
      if (a.dataset.act === "title") return this.title();
      if (a.dataset.act === "next") return this.briefing();
      const p = party[+a.dataset.i], ab = TC.ABILITIES[a.dataset.id];
      if (p && ab && (p.jp || 0) >= ab.jp) {
        p.jp -= ab.jp; p.learned = (p.learned || []).concat(a.dataset.id);
        this.save(); TC.audio.play("levelup"); this.learnScreen();
      }
    };
  }

  /* ------------------------------------------------- event visualisation */
  playEvents(evts, done) {
    const run = i => {
      if (i >= evts.length) { this.busy = false; this.refresh(); return done && done(); }
      const e = evts[i];
      this.busy = true;
      if (e.type === "move") {
        if (this.r.shouldFollow) this.r.focusOn(e.path[e.path.length - 1].x, e.path[e.path.length - 1].y);
        this.r.walk(e.unit, e.from, e.path, () => run(i + 1));
        TC.audio.play("move");
        return;
      }
      if (e.type === "knockback") {
        this.r.walk(e.unit, e.from, [e.to], () => run(i + 1));
        return;
      }
      const delay = this.visualize(e);
      if (delay) setTimeout(() => run(i + 1), delay); else run(i + 1);
    };
    run(0);
  }

  visualize(e) {
    const r = this.r, g = this.battle.grid;
    const at = u => ({ x: u.x, y: u.y, h: g.height(u.x, u.y) });
    switch (e.type) {
      case "damage": {
        const p = at(e.unit);
        const crit = e.crit, back = e.side === "back";
        r.float(p.x, p.y, p.h, (crit ? "✦" : "") + e.amount, crit ? "#ffd86a" : e.unit.team === "P" ? "#ff9d9d" : "#ffffff",
                { size: crit ? 26 : 20 });
        if (back) r.float(p.x, p.y, p.h, "BACK!", "#ffb366", { size: 12, vy: -20, dx: 22 });
        r.flashUnit(e.unit, "#ffffff");
        r.burst(p.x, p.y, p.h + .4, crit ? "#ffd86a" : "#ff8a8a", crit ? 22 : 12, crit ? 1.7 : 1);
        r.shakeBy(crit ? 12 : 5);
        TC.audio.play(crit ? "crit" : "hit");
        this.log(`<span class="${e.unit.team === "P" ? "p" : "e"}">${e.unit.name}</span> takes <b>${e.amount}</b>${crit ? " (CRIT)" : back ? " (back)" : ""}${e.kind === "hazard" ? " from the terrain" : e.kind === "counter" ? " countering" : ""}.`);
        return 110;
      }
      case "heal": {
        const p = at(e.unit);
        r.float(p.x, p.y, p.h, "+" + e.amount, "#8ce8a8", { size: 20 });
        r.flashUnit(e.unit, "#6fd08c");
        r.burst(p.x, p.y, p.h + .4, "#8ce8a8", 12, .8);
        if (e.amount > 0) TC.audio.play("heal");
        return 90;
      }
      case "miss": {
        const p = at(e.unit);
        r.float(p.x, p.y, p.h, "MISS", "#cfd4e0", { size: 16 });
        TC.audio.play("miss");
        this.log(`<span class="${e.by.team === "P" ? "p" : "e"}">${e.by.name}</span> misses <span class="${e.unit.team === "P" ? "p" : "e"}">${e.unit.name}</span>.`);
        return 140;
      }
      case "cast": {
        const p = { x: e.tx, y: e.ty, h: g.height(e.tx, e.ty) };
        const magical = ["mag", "heal", "buff", "revive", "drain"].includes(e.ability.type);
        const dist = TC.manhattan(e.unit, { x: e.tx, y: e.ty });
        if (magical) {
          r.burst(p.x, p.y, p.h + .5, e.ability.type === "heal" ? "#8ce8a8" : "#c9a6ff", 20, 1.3);
          TC.audio.play("magic");
        }
        // A melee swing lunges; anything thrown or shot arcs across the board.
        if (dist <= 1 && dist > 0 && !magical) r.lunge(e.unit, { x: e.tx, y: e.ty });
        else if (dist > 1 && e.ability.type !== "buff" && e.ability.type !== "revive" && !e.ability.shape)
          r.projectile(e.unit, { x: e.tx, y: e.ty }, magical ? "#c9a6ff" : "#ffe9a8");
        this.log(`<span class="${e.unit.team === "P" ? "p" : "e"}">${e.unit.name}</span> uses <b>${e.ability.name}</b>.`, e.unit.team === "P" ? "p" : "e");
        return dist > 1 && !e.ability.shape ? 330 : e.ability.mp ? 200 : 140;
      }
      case "charge": {
        for (const t of e.tiles) r.burst(t.x, t.y, g.height(t.x, t.y) + .2, "#ff9d5c", 4, .6);
        this.log(`<span class="${e.unit.team === "P" ? "p" : "e"}">${e.unit.name}</span> begins casting <b>${e.ability.name}</b>…`, e.unit.team === "P" ? "p" : "e");
        this.syncThreat();
        return 220;
      }
      case "land": {
        for (const t of e.tiles) r.burst(t.x, t.y, g.height(t.x, t.y) + .4, "#ffb066", 14, 1.4);
        r.shakeBy(8);
        TC.audio.play("magic");
        this.log(`<b>${e.ability.name}</b> lands!`, "s");
        this.syncThreat();
        return 200;
      }
      case "fizzle":
        this.log(`<span class="s">${TC.ABILITIES[e.spell.abilityId].name} fizzles — its caster is gone.</span>`);
        this.syncThreat();
        return 120;
      case "rewind":
        return 0;
      case "ko":
        r.burst(e.unit.x, e.unit.y, g.height(e.unit.x, e.unit.y) + .4, "#ffffff", 26, 2);
        r.shakeBy(10);
        TC.audio.play("ko");
        this.log(`<span class="${e.unit.team === "P" ? "p" : "e"}">${e.unit.name}</span> is defeated!`, "s");
        return 260;
      case "revive":
        r.float(e.unit.x, e.unit.y, g.height(e.unit.x, e.unit.y), "REVIVED", "#ffd86a", { size: 16 });
        r.burst(e.unit.x, e.unit.y, g.height(e.unit.x, e.unit.y) + .4, "#ffd86a", 26, 1.6);
        TC.audio.play("levelup");
        this.log(`<span class="g">${e.unit.name} rises again!</span>`, "s");
        return 320;
      case "status": {
        const d = TC.STATUS[e.status];
        r.float(e.unit.x, e.unit.y, g.height(e.unit.x, e.unit.y), `${d.icon} ${d.name}`, d.color, { size: 13, dx: -18 });
        this.log(`<span class="${e.unit.team === "P" ? "p" : "e"}">${e.unit.name}</span> — ${d.name} (${e.turns})`);
        return 110;
      }
      case "counter":
        r.float(e.unit.x, e.unit.y, g.height(e.unit.x, e.unit.y), "COUNTER", "#ffd86a", { size: 14 });
        return 120;
      case "summon":
        r.burst(e.unit.x, e.unit.y, g.height(e.unit.x, e.unit.y) + .4, "#b48ef0", 24, 1.5);
        this.log(`<span class="e">${e.by.name}</span> raises <span class="e">${e.unit.name}</span>!`, "s");
        return 260;
      case "item":
        this.log(`<span class="p">${e.unit.name}</span> uses <b>${e.item.name}</b> on ${e.target.name}.`, "p");
        return 120;
      case "levelup":
        r.float(e.unit.x, e.unit.y, g.height(e.unit.x, e.unit.y), "LEVEL UP!", "#ffd86a", { size: 18 });
        TC.audio.play("levelup");
        this.log(`<span class="g">${e.unit.name} reaches level ${e.unit.level}!</span>`, "s");
        return 300;
      case "turnSkipped":
        if (e.reason === "stun") {
          r.float(e.unit.x, e.unit.y, g.height(e.unit.x, e.unit.y), "STUNNED", "#e8c66a", { size: 15 });
          this.log(`<span class="${e.unit.team === "P" ? "p" : "e"}">${e.unit.name}</span> is stunned and loses the turn.`);
          return 300;
        }
        return 0;
      case "focus":
        r.float(e.unit.x, e.unit.y, g.height(e.unit.x, e.unit.y), "+4 MP", "#7aa5ff", { size: 13 });
        return 0;
      case "end":
        return 300;
      default:
        return 0;
    }
  }

  /* -------------------------------------------------------- player input */
  get me() { const a = this.battle && this.battle.active; return a && a.team === "P" && !a.npc ? a : null; }

  clearOverlays() {
    const o = this.r.overlays;
    o.move.clear(); o.act.clear(); o.aoe.clear(); o.threat.clear(); o.path.length = 0;
    $("preview").style.display = "none";
    this.syncHint();
  }

  enterMove() {
    const u = this.me; if (!u || u.moved) return;
    this.mode = "move"; this.pending = null;
    this.clearOverlays();
    for (const t of this.battle.reachableFor(u).tiles) this.r.overlays.move.add(TC.KEY(t.x, t.y));
    this.hint("Pick a highlighted tile to move. Esc to cancel.");
    this.refresh();
  }

  enterTarget(payload) {
    const u = this.me; if (!u) return;
    this.mode = "target"; this.pending = payload;
    this.clearOverlays();
    const ab = payload.ability || { range: payload.item.range, aoe: 0, vert: 4, target: payload.item.target };
    for (const t of (ab.selfCentered ? [{ x: u.x, y: u.y }] : TC.tilesInRange(this.battle.grid, u.x, u.y, ab)))
      this.r.overlays.act.add(TC.KEY(t.x, t.y));
    this.hint(payload.ability ? `${payload.ability.name} — pick a target. Esc to cancel.`
                              : `${payload.item.name} — pick a target. Esc to cancel.`);
    this.refresh();
  }

  cancel() {
    if (this.busy) return;
    if (this.mode === "move" || this.mode === "target") {
      this.mode = "idle"; this.pending = null;
      this.clearOverlays(); this.hint(""); this.refresh();
      TC.audio.play("cancel");
    }
  }

  onHover(tile) {
    this.hover = tile;
    this.r.cursor = tile;
    const u = this.me;
    if (tile) {
      const occupant = this.battle && (this.battle.unitAt(tile.x, tile.y) || this.battle.koAt(tile.x, tile.y));
      this.showInspect(occupant);
    }
    if (!u || this.busy) return;

    if (this.mode === "move" && tile && this.r.overlays.move.has(TC.KEY(tile.x, tile.y))) {
      const res = this.battle.reachableFor(u);
      const path = TC.pathTo(this.battle.grid, res, u, tile.x, tile.y) || [];
      this.r.overlays.path = path;
    } else if (this.mode === "move") {
      this.r.overlays.path = [];
    }

    if (this.mode === "target" && tile) {
      this.r.overlays.aoe.clear();
      const ab = this.pending.ability;
      if (ab && this.battle.validTarget(u, ab, tile.x, tile.y)) {
        for (const t of TC.aoeTiles(this.battle.grid, tile.x, tile.y, ab)) this.r.overlays.aoe.add(TC.KEY(t.x, t.y));
        this.showPreview(u, ab, tile);
      } else if (!ab) {
        const it = this.pending.item;
        const target = it.target === "ko" ? this.battle.koAt(tile.x, tile.y) : this.battle.unitAt(tile.x, tile.y);
        if (target) this.r.overlays.aoe.add(TC.KEY(tile.x, tile.y));
        $("preview").style.display = target ? "block" : "none";
        if (target) $("preview").innerHTML = `<div class="big">${it.icon} ${it.name}</div><div class="sub">on ${target.name}</div>`;
        this.syncHint();
      } else {
        $("preview").style.display = "none";
        this.syncHint();
      }
    }
  }

  /* The numbers that make a tactics game readable: hit chance and damage. */
  showPreview(u, ab, tile) {
    const b = this.battle;
    const { hits } = b.affected(u, ab, tile.x, tile.y);
    const box = $("preview");
    if (!hits.length) {
      box.style.display = ab.type === "summon" ? "block" : "none";
      if (ab.type === "summon") box.innerHTML = `<div class="big">${ab.name}</div><div class="sub">raise a skeleton here</div>`;
      this.syncHint();
      return;
    }
    box.style.display = "block";
    const rows = hits.map(t => {
      if (ab.type === "heal") {
        const amount = Math.min(t.maxHp - t.hp, Math.round(u.stat("mag") * (ab.power || 1) * 1.6));
        return `<div class="sub">${t.name}: <b style="color:var(--green)">+${amount} HP</b></div>`;
      }
      if (ab.type === "buff") return `<div class="sub">${t.name}: ${TC.STATUS[ab.status.id].name}</div>`;
      if (ab.type === "revive") return `<div class="sub">${t.name}: revive at ${Math.round(t.maxHp * ab.power)} HP</div>`;
      const acc = b.hitChance(u, t, ab);
      const dmg = b.estimateDamage(u, t, ab);
      const side = TC.relativeSide(t, u);
      const lethal = dmg >= t.hp;
      const friendly = t.team === u.team;
      return `<div class="sub">${friendly ? "⚠ " : ""}${t.name}: <b style="color:${friendly ? "var(--red)" : "var(--text)"}">${dmg}</b> dmg · ${acc}% hit
              ${side !== "front" ? `· <span style="color:var(--gold)">${side}</span>` : ""}
              ${lethal ? `<span class="ko">· KO</span>` : ""}</div>`;
    }).join("");
    box.innerHTML = `<div class="big">${ab.name}${ab.mp ? ` <span class="cost">${ab.mp} MP</span>` : ""}</div>${rows}` +
      (ab.charge ? `<div class="sub" style="color:var(--gold)">⏱ charges first — lands on whoever is there then</div>` : "");
    this.syncHint();
  }

  onClick(tile) {
    TC.audio.unlock();
    if (!tile || this.busy || !this.battle) return;
    const u = this.me;
    const clicked = this.battle.unitAt(tile.x, tile.y) || this.battle.koAt(tile.x, tile.y);

    if (this.mode === "deploy") return this.deployClick(tile, clicked);
    if (!u) { this.showInspect(clicked); return; }

    if (this.mode === "move") {
      if (!this.r.overlays.move.has(TC.KEY(tile.x, tile.y))) { this.showInspect(clicked); return; }
      this.battle.moveUnit(u, tile.x, tile.y);
      this.clearOverlays(); this.hint("");
      this.mode = "busy";
      this.playEvents(this.battle.drain(), () => {
        this.mode = this.battle.over ? "over" : "idle";
        if (this.battle.over) return this.finish();
        this.refresh();
      });
      return;
    }

    if (this.mode === "target") {
      const ab = this.pending.ability;
      if (ab) {
        if (!this.battle.validTarget(u, ab, tile.x, tile.y)) { TC.audio.play("cancel"); return; }
        this.battle.useAbility(u, ab, tile.x, tile.y);
      } else {
        const it = this.pending.item;
        if (!this.battle.useItem(u, it.id, tile.x, tile.y)) { TC.audio.play("cancel"); return; }
      }
      this.clearOverlays(); this.hint("");
      this.mode = "busy";
      this.playEvents(this.battle.drain(), () => {
        if (this.battle.checkEnd()) { this.playEvents(this.battle.drain(), () => this.finish()); return; }
        this.mode = "idle";
        // Acting ends the turn unless there is still a move left to spend.
        if (u.moved || !u.alive) this.endTurn(); else this.refresh();
      });
      return;
    }

    // Idle: clicking is a shortcut for "attack that" / "walk there".
    if (clicked && clicked !== u && clicked.alive && clicked.team === "E" && !u.acted) {
      const atk = TC.ABILITIES[u.abilities[0]];
      if (this.battle.validTarget(u, atk, clicked.x, clicked.y)) {
        this.enterTarget({ ability: atk });
        this.onHover(tile);
        return;
      }
    }
    if (!u.moved && !clicked) {
      const res = this.battle.reachableFor(u);
      if (res.tiles.some(t => t.x === tile.x && t.y === tile.y)) {
        this.enterMove();
        this.onHover(tile);
        return;
      }
    }
    this.showInspect(clicked);
  }

  /* -------------------------------------------------------------- panels */
  hint(t) {
    this._hint = t || "";
    this.syncHint();
  }
  syncHint() {
    const previewOn = $("preview").style.display === "block";
    const show = this._hint && !(previewOn && window.innerWidth < 860);
    $("hint").textContent = this._hint || "";
    $("hint").style.display = show ? "block" : "none";
  }

  log(html, cls) {
    const box = $("logbox");
    const d = el("div", cls, html);
    box.prepend(d);
    while (box.children.length > 60) box.lastChild.remove();
  }

  unitCardHTML(u, compact) {
    const j = TC.JOBS[u.job];
    const status = Object.entries(u.status).map(([id, n]) =>
      `<span class="chip" style="color:${TC.STATUS[id].color}">${TC.STATUS[id].icon} ${TC.STATUS[id].name} ${n}</span>`).join("");
    return `
      <div class="uname" style="color:${u.color}">${u.icon} ${u.name}${u.alive ? "" : " <span style='color:var(--red);font-size:11px'>KO</span>"}</div>
      <div class="ujob">${u.job} · Lv ${u.level} · ${u.team === "P" ? "Ally" : "Enemy"}</div>
      <div class="srow"><span>HP</span><b>${u.hp}/${u.maxHp}</b></div>
      <div class="bar hp"><i style="width:${u.hp / u.maxHp * 100}%"></i></div>
      ${u.maxMp ? `<div class="srow"><span>MP</span><b>${u.mp}/${u.maxMp}</b></div>
      <div class="bar mp"><i style="width:${u.mp / u.maxMp * 100}%"></i></div>` : ""}
      ${u.team === "P" && !compact && !u.npc ? `<div class="srow xprow"><span>XP</span><b>${u.xp}/${u.xpToNext}</b> <span style="color:var(--dim)">· ${u.jp} JP</span></div>
      <div class="bar xp"><i style="width:${u.xp / u.xpToNext * 100}%"></i></div>` : ""}
      <div class="grid4">
        <span>ATK <b>${u.stat("atk")}</b></span><span>DEF <b>${u.stat("def")}</b></span>
        <span>MAG <b>${u.stat("mag")}</b></span><span>RES <b>${u.stat("res")}</b></span>
        <span>SPD <b>${u.stat("spd")}</b></span><span>CT <b>${Math.min(100, Math.round(u.ct))}</b></span>
        <span>MOV <b>${u.stat("move")}</b></span><span>JMP <b>${u.stat("jump")}</b></span>
      </div>
      ${status ? `<div class="chips">${status}</div>` : ""}
      ${compact ? "" : `<div class="chips"><span class="chip" style="color:var(--dim)">${j.passive === "none" ? "no passive" : j.passive}</span></div>`}`;
  }

  showInspect(u) {
    const box = $("inspect");
    if (!u) { box.style.display = "none"; return; }
    box.style.display = "block";
    box.innerHTML = this.unitCardHTML(u, true);
  }

  refresh() {
    if (!this.battle) return;
    const b = this.battle;
    const u = b.active;
    $("unitcard").innerHTML = u ? this.unitCardHTML(u) : "<div class='ujob'>—</div>";

    // Turn order preview
    const tl = $("timeline");
    tl.innerHTML = "";
    const slots = window.innerWidth < 520 ? 4 : window.innerWidth < 860 ? 5 : 7;
    const order = (u ? [u] : []).concat(b.forecast(u ? slots - 1 : slots));
    for (const f of order) {
      const s = el("div", "slot" + (f === u ? " now" : "") + (f.spell ? " spell" : ""));
      if (f.spell) {
        const ab = TC.ABILITIES[f.spell.abilityId], caster = b.units[f.spell.casterId];
        s.innerHTML = `<span class="pip" style="background:#ff9d5c22;border:1px dashed #ff9d5c">✦</span><span class="nm">${ab.name}</span>`;
        s.title = `${caster ? caster.name : "?"}'s ${ab.name} is charging`;
      } else {
        s.innerHTML = `<span class="pip" style="background:${f.color}22;border:1px solid ${f.color}">${f.icon}</span><span class="nm">${f.name}</span>`;
        s.onclick = () => this.showInspect(f);
      }
      tl.appendChild(s);
    }

    // Action bar
    const bar = $("actionbar");
    bar.innerHTML = "";
    if (this.mode === "deploy") {
      const z = this.battle.deployZone().length;
      bar.appendChild(el("div", "abtn", `📍 Deploy (${z} tiles)`));
      const go = el("button", "abtn primary", "⚔ Start Battle");
      go.onclick = () => { TC.audio.play("select"); this.beginBattle(); };
      bar.appendChild(go);
      return;
    }
    if (this.mode === "enemy" || this.mode === "over" || this.mode === "busy" || !u || u.team !== "P" || u.npc) {
      if (this.mode === "enemy") bar.appendChild(el("div", "abtn", u && u.npc ? `⏳ ${u.name}…` : "⏳ Enemy turn…"));
      return;
    }
    const add = (label, cls, fn, disabled, key) => {
      const btn = el("button", "abtn " + (cls || ""), label + (key ? ` <span class="key">${key}</span>` : ""));
      btn.disabled = !!disabled;
      btn.onclick = () => { TC.audio.unlock(); TC.audio.play("select"); fn(); };
      bar.appendChild(btn);
      return btn;
    };

    if (this.mode === "idle") {
      add("🥾 Move", "", () => this.enterMove(), u.moved, "M");
      if (u.moved && !u.acted) add("↩ Undo", "", () => {
        this.battle.undoMove(u);
        this.r.unitFx.delete(u.id);
        this.playEvents(this.battle.drain(), () => this.refresh());
      }, false, "U");
      for (const id of u.abilities) {
        const a = TC.ABILITIES[id];
        const cd = u.cooldowns[a.id] || 0;
        const cannot = u.acted || u.mp < (a.mp || 0) || cd > 0;
        add(`${a.name}${a.mp ? ` <span class="cost">${a.mp}MP</span>` : ""}${a.charge ? ` <span class="cost">⏱</span>` : ""}${cd ? ` <span class="cost">${cd}t</span>` : ""}`,
            "", () => this.enterTarget({ ability: a }), cannot);
      }
      const itemIds = Object.keys(b.items).filter(k => b.items[k] > 0);
      if (itemIds.length && !u.acted) {
        add("🎒 Item", "", () => this.itemMenu(), false, "I");
      }
      if (this.turnSnap && (u.moved || u.acted)) add("⟲ Rewind", "", () => this.rewindTurn(), false, "R");
      add("⏹ Wait", "primary", () => this.endTurn(), false, "␣");
    } else if (this.mode === "move" || this.mode === "target") {
      add("✕ Cancel", "danger", () => this.cancel(), false, "Esc");
    }
  }

  itemMenu() {
    const b = this.battle, u = this.me;
    if (!u) return;
    const bar = $("actionbar");
    bar.innerHTML = "";
    for (const id of Object.keys(b.items)) {
      const it = TC.ITEMS[id], n = b.items[id];
      const btn = el("button", "abtn", `${it.icon} ${it.name} <span class="cost">x${n}</span>`);
      btn.disabled = n <= 0;
      btn.title = it.desc;
      btn.onclick = () => { TC.audio.play("select"); this.enterTarget({ item: it }); };
      bar.appendChild(btn);
    }
    const back = el("button", "abtn danger", "✕ Back");
    back.onclick = () => { TC.audio.play("cancel"); this.refresh(); };
    bar.appendChild(back);
  }

  /* --------------------------------------------------------------- input */
  bindInput() {
    const cv = this.r.cv;
    let dragging = false, dragMoved = false, lastX = 0, lastY = 0, pinch = 0;

    const pos = e => {
      const r = cv.getBoundingClientRect();
      const t = e.touches ? e.touches[0] : e;
      return { x: t.clientX - r.left, y: t.clientY - r.top };
    };

    cv.addEventListener("mousemove", e => {
      const p = pos(e);
      if (dragging) {
        this.r.panBy(p.x - lastX, p.y - lastY);
        lastX = p.x; lastY = p.y; dragMoved = true;
        return;
      }
      this.onHover(this.r.screenToTile(p.x, p.y));
    });
    cv.addEventListener("mousedown", e => {
      const p = pos(e);
      if (e.button === 2 || e.button === 1) { dragging = true; dragMoved = false; lastX = p.x; lastY = p.y; }
    });
    window.addEventListener("mouseup", () => { dragging = false; });
    cv.addEventListener("contextmenu", e => { e.preventDefault(); this.cancel(); });
    cv.addEventListener("click", e => {
      const p = pos(e);
      if (dragMoved) { dragMoved = false; return; }
      this.onClick(this.r.screenToTile(p.x, p.y));
    });
    cv.addEventListener("wheel", e => {
      e.preventDefault();
      this.r.zoomBy(e.deltaY > 0 ? 0.9 : 1.1);
    }, { passive: false });

    // Touch: one finger taps to act and drags to pan, two fingers pinch-zoom.
    let touchStart = null, touchMoved = false;
    cv.addEventListener("touchstart", e => {
      TC.audio.unlock();
      if (e.touches.length === 2) {
        pinch = Math.hypot(e.touches[0].clientX - e.touches[1].clientX, e.touches[0].clientY - e.touches[1].clientY);
        return;
      }
      const p = pos(e);
      touchStart = p; touchMoved = false; lastX = p.x; lastY = p.y;
    }, { passive: true });
    cv.addEventListener("touchmove", e => {
      if (e.touches.length === 2 && pinch) {
        e.preventDefault();
        const d = Math.hypot(e.touches[0].clientX - e.touches[1].clientX, e.touches[0].clientY - e.touches[1].clientY);
        this.r.zoomBy(1 + (d - pinch) / 400);
        pinch = d;
        touchMoved = true;
        return;
      }
      const p = pos(e);
      if (touchStart && Math.hypot(p.x - touchStart.x, p.y - touchStart.y) > 12) {
        e.preventDefault();
        touchMoved = true;
        this.r.panBy(p.x - lastX, p.y - lastY);
      }
      lastX = p.x; lastY = p.y;
    }, { passive: false });
    cv.addEventListener("touchend", e => {
      pinch = 0;
      if (!touchStart || touchMoved) { touchStart = null; return; }
      const tile = this.r.screenToTile(touchStart.x, touchStart.y);
      // A tap first previews the tile, a second tap on the same tile commits.
      if (tile && (!this.tapTile || this.tapTile.x !== tile.x || this.tapTile.y !== tile.y) &&
          (this.mode === "move" || this.mode === "target")) {
        this.tapTile = tile;
        this.onHover(tile);
      } else {
        this.tapTile = null;
        this.onHover(tile);
        this.onClick(tile);
      }
      touchStart = null;
    });

    window.addEventListener("keydown", e => {
      if ($("modal").classList.contains("on")) {
        if (e.key === "Enter") { const b = $("sheet").querySelector(".primary"); b && b.click(); }
        return;
      }
      const k = e.key.toLowerCase();
      if (k === "q") this.r.rotateBy(-1);
      else if (k === "e") this.r.rotateBy(1);
      else if (k === "+" || k === "=") this.r.zoomBy(1.15);
      else if (k === "-" || k === "_") this.r.zoomBy(0.87);
      else if (k === "escape") { if (this.mode === "move" || this.mode === "target") this.cancel(); else this.pauseMenu(); }
      else if (k === " ") { e.preventDefault(); if (this.mode === "idle") this.endTurn(); }
      else if (k === "m") { if (this.mode === "idle") this.enterMove(); }
      else if (k === "u") { const u = this.me; if (u && u.moved && !u.acted) { this.battle.undoMove(u); this.r.unitFx.delete(u.id); this.playEvents(this.battle.drain(), () => this.refresh()); } }
      else if (k === "i") { if (this.mode === "idle") this.itemMenu(); }
      else if (k === "h") this.help(() => this.closeModal());
      else if (k === "f") this.r.fit();
      else if (k === "r") this.rewindTurn();
      else if (k === "enter") { if (this.mode === "deploy") this.beginBattle(); }
      else if (k === "tab") {
        e.preventDefault();
        const list = this.battle ? this.battle.living() : [];
        if (list.length) {
          const i = list.indexOf(this.inspecting);
          this.inspecting = list[(i + 1) % list.length];
          this.showInspect(this.inspecting);
          this.r.cursor = { x: this.inspecting.x, y: this.inspecting.y };
        }
      }
    });

    // Toolbar
    $("btnRotL").onclick = () => { TC.audio.play("select"); this.r.rotateBy(-1); };
    $("btnRotR").onclick = () => { TC.audio.play("select"); this.r.rotateBy(1); };
    $("btnZoomIn").onclick = () => this.r.zoomBy(1.18);
    $("btnZoomOut").onclick = () => this.r.zoomBy(0.85);
    $("btnHelp").onclick = () => this.help(() => this.closeModal());
    $("btnMenu").onclick = () => { TC.audio.play("select"); this.pauseMenu(); };
    const syncAudioButtons = () => {
      $("btnSound").classList.toggle("off", !TC.audio.enabled);
      $("btnMusic").classList.toggle("off", !TC.audio.musicOn);
    };
    $("btnSound").onclick = () => { TC.audio.unlock(); TC.audio.setSound(!TC.audio.enabled); syncAudioButtons(); };
    $("btnMusic").onclick = () => { TC.audio.unlock(); TC.audio.setMusic(!TC.audio.musicOn); syncAudioButtons(); };
    syncAudioButtons();

    window.addEventListener("resize", () => {
      this.r.resize();
      this.r.fit();
      if (this.battle && this.battle.active && this.r.shouldFollow)
        this.r.focusOn(this.battle.active.x, this.battle.active.y, null, true);
      this.refresh();
      this.syncHint();
    });
  }

  frame(t) {
    const dt = Math.min(0.05, (t - this.last) / 1000);
    this.last = t;
    if (this.battle) {
      this.r.draw(dt);
    } else {
      this.r.ctx.setTransform(this.r.dpr, 0, 0, this.r.dpr, 0, 0);
      this.r.ctx.clearRect(0, 0, this.r.vw, this.r.vh);
    }
    requestAnimationFrame(x => this.frame(x));
  }
}
TC.Game = Game;
