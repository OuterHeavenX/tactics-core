#!/usr/bin/env node
/* Browser playtest for the HTML5 build.
 *
 * Serves the repository over HTTP, then drives the real game through Playwright
 * at three viewport sizes: it starts a campaign, checks the isometric picking
 * maths at every camera rotation, moves and attacks through the same code path
 * a person's clicks take, and plays a whole battle to a result.
 *
 *   npm install playwright && npx playwright install chromium
 *   node tools/playtest.js
 */
"use strict";
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..');
const MIME = { '.html':'text/html', '.js':'text/javascript', '.css':'text/css', '.svg':'image/svg+xml' };
const PORT = Number(process.env.PORT || 8123);

const server = http.createServer((req,res)=>{
  let p = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
  if (p.endsWith('/')) p += 'index.html';
  fs.readFile(p,(e,d)=>{ if(e){res.writeHead(404);res.end('nf');return;}
    res.writeHead(200,{'Content-Type':MIME[path.extname(p)]||'application/octet-stream'}); res.end(d); });
});

(async () => {
  await new Promise(r => server.listen(PORT, r));
  const launchOpts = {};
  if (process.env.CHROMIUM_PATH) launchOpts.executablePath = process.env.CHROMIUM_PATH;
  const browser = await chromium.launch(launchOpts);
  const results = [];
  const check = (name, ok, extra) => { results.push([ok,name,extra||'']); console.log((ok?'  ✓ ':'  ✗ ')+name+(extra?'  '+extra:'')); };

  for (const vp of [{name:'desktop',viewport:{width:1440,height:900}},
                    {name:'tablet',viewport:{width:820,height:1180},hasTouch:true},
                    {name:'phone',viewport:{width:390,height:844},isMobile:true,hasTouch:true,deviceScaleFactor:2}]) {
    const ctx = await browser.newContext(vp);
    const page = await ctx.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(String(e)));
    page.on('console', m => { if (m.type()==='error') errors.push('console: '+m.text()); });
    console.log('\n['+vp.name+' '+vp.viewport.width+'x'+vp.viewport.height+']');
    await page.goto(`http://localhost:${PORT}/`, { waitUntil:'networkidle' });

    check('title screen shown', await page.isVisible('#modal.on'));
    check('party roster listed', (await page.locator('#sheet .roster .r').count()) === 5);

    await page.click('[data-act="new"]');
    check('briefing shown', await page.locator('#sheet h2').innerText().then(t=>t.includes('Chapter 1')));
    await page.click('[data-act="go"]');
    await page.waitForTimeout(1500);

    check('modal closed, battle running', !(await page.isVisible('#modal.on')));
    check('no JS errors so far', errors.length===0, errors.slice(0,2).join(' | '));

    // Canvas actually painted something
    const painted = await page.evaluate(() => {
      const c = document.getElementById('cv');
      const g = c.getContext('2d');
      const d = g.getImageData(0,0,c.width,c.height).data;
      let nonEmpty = 0, colors = new Set();
      for (let i=0;i<d.length;i+=4*997) { if (d[i+3]>0) nonEmpty++; colors.add(d[i]+','+d[i+1]+','+d[i+2]); }
      return { nonEmpty, distinct: colors.size };
    });
    check('canvas rendered', painted.nonEmpty > 100 && painted.distinct > 40, JSON.stringify(painted));

    const st = await page.evaluate(() => {
      const g = window.TCGAME, b = g.battle;
      return { units: b.units.length, grid: b.grid.cols+'x'+b.grid.rows, active: b.active && b.active.name,
               team: b.active && b.active.team, mode: g.mode, rot: g.r.rot, zoom: +g.r.cam.zoom.toFixed(2) };
    });
    check('battle state populated', st.units===10 && st.grid==='12x10', JSON.stringify(st));

    // Camera rotation round-trips and still picks the right tile
    const pick = await page.evaluate(async () => {
      const g = window.TCGAME, out = [];
      for (let i=0;i<4;i++) {
        g.r.rot = i; g.r.rotT = 1; g.r.centerOnBoard();
        g.r.draw(0.016);
        let hits = 0, total = 0, occluded = 0; const wrong = [];
        for (let y=0;y<g.battle.grid.rows;y++) for (let x=0;x<g.battle.grid.cols;x++) {
          const t = g.battle.grid.at(x,y); if (t.terrain.void) continue;
          const p = g.r.toScreen(g.r.project(x,y,t.h));
          if (p.x<0||p.y<0||p.x>g.r.vw||p.y>g.r.vh) continue;
          total++;
          const back = g.r.screenToTile(p.x, p.y);
          if (back && back.x===x && back.y===y) { hits++; continue; }
          // A miss is only legitimate when a taller tile nearer the camera covers it.
          if (back) {
            const bt = g.battle.grid.at(back.x, back.y);
            const d0 = g.r.project(x,y,t.h).depth, d1 = g.r.project(back.x,back.y,bt.h).depth;
            if (d1 > d0 && bt.h > t.h) { occluded++; continue; }
          }
          wrong.push(x+','+y+'->'+(back?back.x+','+back.y:'null'));
        }
        out.push({rot:i, hits, occluded, wrong: wrong.slice(0,5), total});
      }
      g.r.rot = 0; g.r.centerOnBoard();
      return out;
    });
    const pickOk = pick.every(p => p.total>0 && p.wrong.length===0);
    check('screen->tile picking exact at all 4 rotations (misses are genuine occlusion)', pickOk, JSON.stringify(pick));

    // Drive a full player turn through the real UI path
    const turn = await page.evaluate(async () => {
      const g = window.TCGAME, b = g.battle;
      const sleep = ms => new Promise(r=>setTimeout(r,ms));
      // fast-forward to a player turn
      for (let i=0;i<40 && (!b.active || b.active.team!=='P' || g.mode!=='idle'); i++) await sleep(250);
      if (!b.active || b.active.team!=='P') return { err:'no player turn' };
      const u = b.active;
      const before = { x:u.x, y:u.y, moved:u.moved };
      g.enterMove();
      const tiles = [...g.r.overlays.move];
      const t = tiles[Math.floor(tiles.length/2)].split(',').map(Number);
      g.onClick({x:t[0], y:t[1]});
      await sleep(1600);
      const afterMove = { x:u.x, y:u.y, moved:u.moved, mode:g.mode };
      const undone = b.undoMove(u); b.drain();
      return { before, afterMove, moveWorked: afterMove.moved && (afterMove.x!==before.x||afterMove.y!==before.y), undone };
    });
    check('player can move via the UI', turn.moveWorked === true, JSON.stringify(turn));
    check('move is undoable before acting', turn.undone === true);

    // Full battle driven through the real UI code path, with the shipped AI
    // choosing the player's moves so the test is a fair fight.
    const fight = await page.evaluate(async () => {
      const g = window.TCGAME, b = g.battle;
      const sleep = ms => new Promise(r=>setTimeout(r,ms));
      let acted = false, enemyMoved = false;
      for (let step=0; step<3000 && !b.over; step++) {
        await sleep(25);
        if (g.busy || g.mode==='busy') continue;
        if (b.active && b.active.team==='E') { enemyMoved = true; continue; }
        if (!b.active || b.active.team!=='P' || g.mode!=='idle') continue;
        const u = b.active;
        const plan = TC.planTurn(b, u);
        if (plan.move && !u.moved) { g.enterMove(); g.onClick(plan.move); continue; }
        if (plan.ability && !u.acted && b.validTarget(u, plan.ability, plan.tx, plan.ty)) {
          g.enterTarget({ability: plan.ability}); g.onClick({x:plan.tx, y:plan.ty});
          acted = true; continue;
        }
        g.endTurn();
      }
      return { acted, enemyMoved, over: b.over, turns: b.turn,
               pAlive: b.living('P').length, eAlive: b.living('E').length };
    });
    check('player attacks resolve', fight.acted === true);
    check('enemy AI takes its turns', fight.enemyMoved === true);
    check('battle reaches a result', !!fight.over, JSON.stringify(fight));
    await page.waitForSelector('#modal.on', { timeout: 15000 }).catch(()=>{});
    check('result screen shown', await page.isVisible('#modal.on'),
          await page.locator('#sheet h1').innerText().catch(()=>'-'));
    check('progress saved after a win', fight.over!=='victory' ||
          await page.evaluate(()=>!!localStorage.getItem('tc.save.v2')));
    check('no JS errors during full battle', errors.length===0, errors.slice(0,3).join(' | '));

    if (process.env.SHOT_DIR) await page.screenshot({ path: `${process.env.SHOT_DIR}/shot-${vp.name}-end.png` });
    await ctx.close();
  }
  await browser.close();
  server.close();
  const failed = results.filter(r=>!r[0]);
  console.log(`\n${results.length-failed.length}/${results.length} checks passed`);
  process.exit(failed.length?1:0);
})();
