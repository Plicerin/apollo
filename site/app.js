'use strict';
// Runs the cartridge on the page: picture, sound, keyboard, gamepad, touch.

// The AY-3-8914 sound chip, stepped at the audio rate. The console has one, the ECS adds another.
function makeAyClass() {
  const VOL = [0, 0.0137, 0.0205, 0.0291, 0.0423, 0.0618, 0.0847, 0.1369, 0.1691, 0.2647, 0.3527, 0.4499, 0.5701, 0.6873, 0.8482, 1.0];
  return class AY {
    constructor(rate) {
      this.perSample = (3579545 / 2 / 8) / rate;
      this.reset();
    }
    reset() {
      this.r = new Uint8Array(16); this.r[8] = 0x3F;
      this.tc = [0, 0, 0]; this.to = [0, 0, 0];
      this.nc = 0; this.nps = 0; this.rng = 1; this.no = 0;
      this.ec = 0; this.es = 0; this.ea = 0; this.eh = 0; this.ealt = 0; this.eholding = 1; this.ev = 0;
      this.acc = 0; this.hpX = 0; this.hpY = 0; this.last = 0;
    }
    write(reg, v) {
      this.r[reg] = v;
      if (reg === 10) {
        this.ea = (v & 4) ? 15 : 0;
        if (v & 8) { this.eh = v & 1; this.ealt = v & 2; } else { this.eh = 1; this.ealt = this.ea; }
        this.eholding = 0; this.es = 15; this.ec = 0; this.ev = this.es ^ this.ea;
      }
    }
    tick() {
      const r = this.r;
      for (let c = 0; c < 3; c++) {
        const p = (r[c] | ((r[4 + c] & 15) << 8)) || 1;
        if (++this.tc[c] >= p) { this.tc[c] = 0; this.to[c] ^= 1; }
      }
      const np = (r[9] & 31) || 1;
      if (++this.nc >= np) {
        this.nc = 0; this.nps ^= 1;
        if (this.nps) { const bit = (this.rng ^ (this.rng >> 3)) & 1; this.rng = (this.rng >> 1) | (bit << 16); this.no = this.rng & 1; }
      }
      if (!this.eholding) {
        const ep = ((r[3] | (r[7] << 8)) || 1) * 2;
        if (++this.ec >= ep) {
          this.ec = 0; this.es--;
          if (this.es < 0) {
            if (this.eh) { if (this.ealt) this.ea ^= 15; this.eholding = 1; this.es = 0; }
            else { if (this.ealt) this.ea ^= 15; this.es &= 15; }
          }
          this.ev = this.es ^ this.ea;
        }
      }
      const mix = r[8];
      let s = 0;
      for (let c = 0; c < 3; c++) {
        const on = (this.to[c] | ((mix >> c) & 1)) & (this.no | ((mix >> (3 + c)) & 1));
        if (!on) continue;
        const vr = r[11 + c];
        s += (vr & 0x30) ? VOL[this.ev] : VOL[vr & 15];
      }
      return s;
    }
    sample() {
      this.acc += this.perSample;
      const n = this.acc | 0; this.acc -= n;
      let sum = 0;
      for (let k = 0; k < n; k++) sum += this.tick();
      const x = n ? sum / n : this.last; this.last = x;
      const y = x - this.hpX + 0.998 * this.hpY; this.hpX = x; this.hpY = y;
      return y * 0.26;
    }
  };
}

class Sound {
  constructor() { this.ctx = null; this.node = null; this.gain = null; this.volume = 0.7; this.muted = false; this.batch = []; }
  async start() {
    if (this.ctx) { try { await this.ctx.resume(); } catch (e) { /* the browser may refuse */ } return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    const ctx = new AC();
    this.ctx = ctx;
    this.gain = ctx.createGain();
    this.gain.gain.value = this.level();
    this.gain.connect(ctx.destination);
    try {
      const src = 'const AY=(' + makeAyClass.toString() + ')();' +
        'class P extends AudioWorkletProcessor{constructor(){super();this.a=[new AY(sampleRate),new AY(sampleRate)];this.q=[];' +
        'this.port.onmessage=e=>{const m=e.data;if(m.reset){this.a[0].reset();this.a[1].reset();this.q.length=0;return;}for(const w of m)this.q.push(w);};}' +
        'process(i,o){const out=o[0][0];for(let n=0;n<out.length;n++){const t=currentTime+n/sampleRate;' +
        'while(this.q.length&&this.q[0][0]<=t){const w=this.q.shift();this.a[w[1]].write(w[2],w[3]);}' +
        'out[n]=this.a[0].sample()+this.a[1].sample();}return true;}}registerProcessor("apollo-psg",P);';
      const url = URL.createObjectURL(new Blob([src], { type: 'text/javascript' }));
      await ctx.audioWorklet.addModule(url);
      URL.revokeObjectURL(url);
      this.node = new AudioWorkletNode(ctx, 'apollo-psg', { numberOfInputs: 0, outputChannelCount: [1] });
      this.node.connect(this.gain);
      this.post = m => this.node.port.postMessage(m);
    } catch (e) {
      // No worklets here: fall back to the older audio node on the main thread.
      const AY = makeAyClass();
      const a = [new AY(ctx.sampleRate), new AY(ctx.sampleRate)];
      const q = [];
      const sp = ctx.createScriptProcessor(1024, 0, 1);
      sp.onaudioprocess = ev => {
        const out = ev.outputBuffer.getChannelData(0), t0 = ev.playbackTime;
        for (let n = 0; n < out.length; n++) {
          const t = t0 + n / ctx.sampleRate;
          while (q.length && q[0][0] <= t) { const w = q.shift(); a[w[1]].write(w[2], w[3]); }
          out[n] = a[0].sample() + a[1].sample();
        }
      };
      sp.connect(this.gain);
      this.node = sp;
      this.post = m => { if (m.reset) { a[0].reset(); a[1].reset(); q.length = 0; } else for (const w of m) q.push(w); };
    }
    try { await ctx.resume(); } catch (e) { /* the browser may refuse */ }
  }
  level() { return this.muted ? 0 : this.volume; }
  applyLevel() { if (this.gain) this.gain.gain.value = this.level(); }
  add(chip, reg, v, cyc) {
    if (!this.ctx || !this.post) return;
    this.batch.push([this.ctx.currentTime + 0.06 + cyc / 894886, chip, reg, v]);
  }
  flush() { if (this.batch.length && this.post) { this.post(this.batch); this.batch = []; } else this.batch.length = 0; }
  clear() { this.batch.length = 0; if (this.post) this.post({ reset: true }); }
  suspend() { if (this.ctx) this.ctx.suspend().catch(() => {}); }
  resume() { if (this.ctx) this.ctx.resume().catch(() => {}); }
}

(function main() {
  const $ = (s, el) => (el || document).querySelector(s);
  const $$ = (s, el) => Array.from((el || document).querySelectorAll(s));
  const player = $('#player'), canvas = $('#screen'), overlay = $('#overlay'), overTitle = $('#over-title'), overText = $('#over-text');
  const btnPlay = $('#over-go'), btnPause = $('#b-pause'), btnSound = $('#b-sound'), vol = $('#b-vol');
  const statusEl = $('#status');

  const sound = new Sound();
  const m = new Inty({ onPsg: (c, r, v, cyc) => sound.add(c, r, v, cyc) });
  m.loadRom(Uint8Array.from(atob(window.APOLLO_ROM), c => c.charCodeAt(0)));

  // picture
  const ctx = canvas.getContext('2d');
  const small = document.createElement('canvas');
  small.width = SCREEN_W; small.height = SCREEN_H;
  const sctx = small.getContext('2d');
  const img = sctx.createImageData(SCREEN_W, SCREEN_H);
  const pix = new Uint32Array(img.data.buffer);
  const pal = INTY_PALETTE.map(c => (255 << 24) | (c[2] << 16) | (c[1] << 8) | c[0]);
  ctx.imageSmoothingEnabled = false;
  function paint() {
    const p = m.pic;
    for (let i = 0; i < p.length; i++) pix[i] = pal[p[i]];
    sctx.putImageData(img, 0, 0);
    ctx.drawImage(small, 0, 0, canvas.width, canvas.height);
  }

  // input
  const keys = new Set();
  // A quick tap must still reach the game, which looks at the controller once a frame
  const MIN_HOLD = 3;
  const pressedAt = new Map(), letGo = new Set();
  let pointerDisc = -1, heldSide = 0, heldKey = 0, padDisc = -1, padSide = 0, tapCode = 0, tapUntil = 0;
  // A quick tap on the drawn controller still lasts long enough for the game to see
  function tap(code) { tapCode |= code; tapUntil = m.frame + MIN_HOLD; }

  function keyboardDisc() {
    const u = keys.has('ArrowUp') || keys.has('KeyW'), d = keys.has('ArrowDown') || keys.has('KeyS');
    const l = keys.has('ArrowLeft') || keys.has('KeyA'), r = keys.has('ArrowRight') || keys.has('KeyD');
    const dx = (r ? 1 : 0) - (l ? 1 : 0), dy = (u ? 1 : 0) - (d ? 1 : 0);
    if (!dx && !dy) return -1;
    return Math.round((Math.atan2(dy, dx) + 2 * Math.PI) % (2 * Math.PI) / (Math.PI / 8)) % 16;
  }
  function readGamepad() {
    padDisc = -1; padSide = 0;
    let list;
    try { list = navigator.getGamepads ? navigator.getGamepads() : []; } catch (e) { return; }
    for (const g of list) {
      if (!g) continue;
      const b = i => g.buttons[i] && g.buttons[i].pressed;
      let x = g.axes[0] || 0, y = g.axes[1] || 0;
      if (b(12)) y = -1; if (b(13)) y = 1; if (b(14)) x = -1; if (b(15)) x = 1;
      if (x * x + y * y > 0.2) padDisc = Math.round((Math.atan2(-y, x) + 2 * Math.PI) % (2 * Math.PI) / (Math.PI / 8)) % 16;
      if (b(0)) padSide |= PAD.top;
      if (b(1) || b(2)) padSide |= PAD.lowerLeft;
      if (b(3) || b(8)) padSide |= PAD.key[1];
      return;
    }
  }
  function readInput() {
    let code = 0;
    const kd = keyboardDisc();
    const disc = pointerDisc >= 0 ? pointerDisc : (kd >= 0 ? kd : padDisc);
    if (disc >= 0) code |= PAD.disc[disc];
    if (keys.has('Space') || keys.has('Enter') || keys.has('NumpadEnter') || keys.has('ShiftRight')) code |= PAD.top;
    if (keys.has('KeyB')) code |= PAD.lowerLeft;
    if (keys.has('KeyM')) code |= PAD.key[1];
    for (let n = 0; n < 10; n++) if (keys.has('Digit' + n) || keys.has('Numpad' + n)) code |= PAD.key[n];
    if (m.frame >= tapUntil) tapCode = 0;
    code |= heldSide | heldKey | padSide | tapCode;
    m.pads[1] = code;
    for (const k of letGo) {
      if (m.frame - (pressedAt.get(k) || 0) >= MIN_HOLD) { keys.delete(k); letGo.delete(k); }
    }
  }

  // state: 'attract' runs silently behind the Play button
  let state = 'attract', paused = false, last = 0, acc = 0;
  const FRAME_MS = 1000 / 59.92;

  // Skipping ahead drops the sound writes, so hand the chips their registers afterwards
  function fastForward(n) {
    for (let i = 0; i < n; i++) m.runFrame();
    sound.batch.length = 0;
    for (let c = 0; c < 2; c++) for (let reg = 0; reg < 14; reg++) if (reg !== 10) sound.add(c, reg, m.psg[c][reg], 0);
  }
  function press(code, n) { m.pads[1] = code; fastForward(n); m.pads[1] = 0; fastForward(14); }

  function setOverlay(kind) {
    if (kind === 'attract') {
      overlay.hidden = false; overlay.classList.add('low');
      overTitle.textContent = 'Ready when you are';
      overText.textContent = 'The demo pilot starts flying in a few seconds.';
      btnPlay.textContent = 'Play';
    } else if (kind === 'paused') {
      overlay.hidden = false; overlay.classList.remove('low');
      overTitle.textContent = 'Paused';
      overText.textContent = 'Your flight is holding here.';
      btnPlay.textContent = 'Continue';
    } else overlay.hidden = true;
  }
  function setPaused(p) {
    paused = p;
    btnPause.textContent = p ? 'Continue' : 'Pause';
    btnPause.setAttribute('aria-pressed', p ? 'true' : 'false');
    if (p) { sound.suspend(); if (state === 'play') setOverlay('paused'); }
    else { sound.resume(); setOverlay('none'); }
  }
  function say(t) { statusEl.textContent = t; }

  async function begin(how) {
    await sound.start();
    state = 'play';
    sound.clear();
    m.reset();
    keys.clear(); letGo.clear(); heldSide = 0; heldKey = 0; pointerDisc = -1; tapCode = 0;
    fastForward(40);
    if (how === 'title') say('On the title screen. Press the button to start at Stage 1.');
    else if (how === 'demo') { fastForward(900); say('The demo pilot is flying. Press any button to take over at the title screen.'); }
    else { press(PAD.key[how], 8); say('Stage ' + how + ' is lined up. Press the button to go.'); }
    setPaused(false);
    setOverlay('none');
    canvas.focus({ preventScroll: true });
    acc = 0; last = performance.now();
  }

  // the loop
  function loop(now) {
    requestAnimationFrame(loop);
    if (paused || document.hidden) { last = now; return; }
    acc += Math.min(now - last, 250);
    last = now;
    if (acc < FRAME_MS) return;
    readGamepad();
    readInput();
    let ran = false;
    while (acc >= FRAME_MS) { m.runFrame(); acc -= FRAME_MS; ran = true; }
    if (ran) { paint(); sound.flush(); }
  }

  // keyboard, only while the game has focus
  const GAME_KEYS = /^(Arrow(Up|Down|Left|Right)|Key[WASDBM]|Space|Enter|NumpadEnter|ShiftRight|Digit[0-9]|Numpad[0-9])$/;
  canvas.addEventListener('keydown', e => {
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    if (e.code === 'KeyP' || e.code === 'Escape') { if (state === 'play') { setPaused(!paused); e.preventDefault(); } return; }
    if (GAME_KEYS.test(e.code)) {
      e.preventDefault();
      if (state === 'attract') { if (!e.repeat && (e.code === 'Space' || e.code === 'Enter')) begin('title'); return; }
      if (paused) { if (!e.repeat && (e.code === 'Space' || e.code === 'Enter')) { setPaused(false); } return; }
      if (!e.repeat) pressedAt.set(e.code, m.frame);
      keys.add(e.code);
      letGo.delete(e.code);
    }
  });
  canvas.addEventListener('keyup', e => { if (keys.has(e.code)) letGo.add(e.code); });
  canvas.addEventListener('blur', () => { keys.clear(); letGo.clear(); });
  window.addEventListener('blur', () => { keys.clear(); letGo.clear(); if (state === 'play' && !paused) setPaused(true); });
  document.addEventListener('visibilitychange', () => { if (document.hidden && state === 'play' && !paused) setPaused(true); });
  player.addEventListener('focusout', e => {
    if (state === 'play' && !paused && e.relatedTarget && !player.contains(e.relatedTarget)) setPaused(true);
  });
  canvas.addEventListener('pointerdown', () => {
    canvas.focus({ preventScroll: true });
    if (state === 'attract') begin('title');
    else if (paused) setPaused(false);
  });

  // on-screen controller
  const refocus = () => { if (matchMedia('(hover: hover)').matches) canvas.focus({ preventScroll: true }); };
  function ensurePlaying() { if (state === 'attract') { begin('title'); return false; } if (paused) setPaused(false); return true; }
  function holdable(el, down, up) {
    el.addEventListener('pointerdown', e => {
      e.preventDefault();
      if (el.setPointerCapture) { try { el.setPointerCapture(e.pointerId); } catch (x) { /* ok */ } }
      el.classList.add('down');
      if (ensurePlaying()) down();
    });
    const end = e => { el.classList.remove('down'); up(); refocus(); };
    el.addEventListener('pointerup', end);
    el.addEventListener('pointercancel', end);
    el.addEventListener('lostpointercapture', () => { el.classList.remove('down'); up(); });
    el.addEventListener('contextmenu', e => e.preventDefault());
  }
  $$('[data-side]').forEach(b => {
    const code = b.dataset.side === 'top' ? PAD.top : PAD.lowerLeft;
    holdable(b, () => { heldSide |= code; tap(code); }, () => { heldSide &= ~code; });
  });
  $$('[data-key]').forEach(b => {
    const v = b.dataset.key;
    const code = v === 'clear' ? PAD.clear : v === 'enter' ? PAD.enter : PAD.key[+v];
    holdable(b, () => { heldKey = code; tap(code); }, () => { heldKey = 0; });
  });
  $$('[data-disc]').forEach(disc => {
    const knob = disc.querySelector('.knob'), R = disc.querySelector('.hit').r.baseVal.value * 0.55;
    function discAt(e) {
      const r = disc.getBoundingClientRect();
      const dx = e.clientX - (r.left + r.width / 2), dy = (r.top + r.height / 2) - e.clientY;
      const a = (Math.atan2(dy, dx) + 2 * Math.PI) % (2 * Math.PI);
      pointerDisc = Math.round(a / (Math.PI / 8)) % 16;
      const k = pointerDisc * Math.PI / 8;
      knob.setAttribute('transform', 'translate(' + (Math.cos(k) * R).toFixed(1) + ' ' + (-Math.sin(k) * R).toFixed(1) + ')');
    }
    disc.addEventListener('pointerdown', e => {
      e.preventDefault();
      try { disc.setPointerCapture(e.pointerId); } catch (x) { /* ok */ }
      disc.classList.add('down');
      if (ensurePlaying()) discAt(e);
    });
    disc.addEventListener('pointermove', e => { if (disc.classList.contains('down')) discAt(e); });
    const discEnd = () => { disc.classList.remove('down'); pointerDisc = -1; knob.removeAttribute('transform'); refocus(); };
    disc.addEventListener('pointerup', discEnd);
    disc.addEventListener('pointercancel', discEnd);
  });

  // buttons
  btnPlay.addEventListener('click', () => { if (state === 'attract') begin('title'); else if (paused) { setPaused(false); canvas.focus({ preventScroll: true }); } });
  $('#b-new').addEventListener('click', () => begin('title'));
  $('#b-demo').addEventListener('click', () => begin('demo'));
  btnPause.addEventListener('click', () => {
    if (state === 'attract') return;
    setPaused(!paused);
    if (!paused) canvas.focus({ preventScroll: true });
  });
  btnSound.addEventListener('click', () => {
    sound.muted = !sound.muted;
    btnSound.textContent = sound.muted ? 'Sound off' : 'Sound on';
    btnSound.setAttribute('aria-pressed', sound.muted ? 'false' : 'true');
    sound.applyLevel();
    refocus();
  });
  vol.addEventListener('input', () => { sound.volume = vol.value / 100; sound.applyLevel(); });
  $$('[data-stage]').forEach(b => b.addEventListener('click', e => {
    e.preventDefault();
    const n = +b.dataset.stage;
    if (b.closest('#stages')) player.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start' });
    begin(n);
  }));
  const go = $('#hero-play');
  if (go) go.addEventListener('click', () => { begin('title'); });

  // Start silently on the title screen, so the page opens with the game on it
  fastForward(120);
  m.render();
  paint();
  setOverlay('attract');
  last = performance.now();
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) { paused = true; overText.textContent = 'Press Play to start.'; }
  requestAnimationFrame(loop);
})();
