'use strict';
// A small Intellivision for the browser: CP-1610 CPU, STIC picture chip, and the
// memory map Apollo uses, with an ECS (second sound chip and its RAM) plugged in.
// Written for this game. It carries no Mattel code: there is no Executive, the
// CPU starts straight at the cartridge's program, and the character set is our own.

// ---------------------------------------------------------------- character set
// 8 bytes a character, 64 characters from space, top row first.
const FONT_HEX =
  '0000000000000000 1818181818001800 6C6C480000000000 6CFE6C6CFE6C0000 ' +
  '187EC07C06FC1800 C4CC18306646 0000 386C3876DCCC7600 1818300000000000 ' +
  '0C18303030180C00 30180C0C0C183000 006C38FE386C0000 0018187E18180000 ' +
  '0000000000181830 0000007E00000000 0000000000181800 060C183060C00000 ' +
  '7CC6CED6E6C67C00 183818181818 7E00 7CC6061C70C0FE00 7CC6063C06C67C00 ' +
  '1C3C6CCCFE0C0C00 FEC0FC0606C67C00 3C60C0FCC6C67C00 FEC60C1830303000 ' +
  '7CC6C67CC6C67C00 7CC6C67E060C7800 0018180018180000 0018180018183000 ' +
  '0C18306030180C00 0000 7E007E000000 6030180C18306000 7CC60C1818001800 ' +
  '7CC6DEDEDCC07C00 386CC6C6FEC6C600 FCC6C6FCC6C6FC00 7CC6C0C0C0C67C00 ' +
  'F8CCC6C6C6CCF800 FEC0C0F8C0C0FE00 FEC0C0F8C0C0C000 7CC6C0CEC6C67E00 ' +
  'C6C6C6FEC6C6C600 7E18181818187E00 1E060606C6C67C00 C6CCD8F0D8CCC600 ' +
  'C0C0C0C0C0C0FE00 C6EEFED6C6C6C600 C6E6F6DECEC6C600 7CC6C6C6C6C67C00 ' +
  'FCC6C6FCC0C0C000 7CC6C6C6D6CC7600 FCC6C6FCD8CCC600 7CC6C07C06C67C00 ' +
  '7E18181818181800 C6C6C6C6C6C67C00 C6C6C6C66C381000 C6C6C6D6FEEEC600 ' +
  'C6C66C386CC6C600 6666663C18181800 FE060C183060FE00 3C30303030303C00 ' +
  'C06030180C060000 3C0C0C0C0C0C3C00 10386CC600000000 00000000 0000FE00';

function makeGrom() {
  const hex = FONT_HEX.replace(/ /g, '');
  const g = new Uint8Array(256 * 8);
  for (let i = 0; i < 64 * 8; i++) g[i] = parseInt(hex.substr(i * 2, 2), 16);
  // Lower case shows as capitals. The game doesn't use it, but it shouldn't be blank.
  for (let c = 65; c <= 90; c++) for (let r = 0; r < 8; r++) g[(c - 32 + 32) * 8 + r] = g[(c - 32) * 8 + r];
  return g;
}

// The console's 16 colours, as jzIntv shows them.
const INTY_PALETTE = [
  [0x00, 0x00, 0x00], [0x14, 0x38, 0xF7], [0xE3, 0x5B, 0x0E], [0xCB, 0xF1, 0x68],
  [0x00, 0x94, 0x28], [0x07, 0xC2, 0x00], [0xFF, 0xFF, 0x01], [0xFF, 0xFF, 0xFF],
  [0xC8, 0xC8, 0xC8], [0x23, 0xCE, 0xC3], [0xFD, 0x99, 0x18], [0x3A, 0x8A, 0x00],
  [0xF0, 0x46, 0x3C], [0xD3, 0x83, 0xFF], [0x48, 0xF6, 0x01], [0xB8, 0x11, 0x78],
];

// Hand controller codes, as the game sees them after inverting the port.
const PAD = {
  disc: [0x02, 0x06, 0x16, 0x14, 0x04, 0x0C, 0x1C, 0x18, 0x08, 0x09, 0x19, 0x11, 0x01, 0x03, 0x13, 0x12], // E, then counter-clockwise
  top: 0xA0, lowerLeft: 0x60, lowerRight: 0xC0,
  key: [0x48, 0x81, 0x41, 0x21, 0x82, 0x42, 0x22, 0x84, 0x44, 0x24], // 0-9
  clear: 0x88, enter: 0x28,
};

const SCREEN_W = 176, SCREEN_H = 224;              // 160 x 96 picture plus an 8 pixel border; rows are half pixels
const CYCLES_FRAME = 14934, CYCLES_VBLANK = 3796, CYCLES_STOLEN = 1320;

class Inty {
  constructor(opts) {
    opts = opts || {};
    this.onPsg = opts.onPsg || null;           // (chip, reg, value, frameCycle)
    this.mem = new Uint16Array(65536).fill(0xFFFF);
    this.grom = opts.grom || makeGrom();
    for (let i = 0; i < 0x800; i++) this.mem[0x3000 + i] = this.grom[i] | 0;
    this.gram = new Uint8Array(512);
    this.stic = new Uint16Array(64);
    this.psg = [new Uint8Array(16), new Uint8Array(16)];
    this.pads = [0, 0];                         // pressed codes
    this.rngSeed = opts.seed === undefined ? (Math.random() * 0x7FFFFFFF) | 0 : opts.seed;
    this.pic = new Uint8Array(SCREEN_W * SCREEN_H);
    this.fgm = new Uint8Array(SCREEN_W * SCREEN_H);
    this.mobC = new Int8Array(SCREEN_W * SCREEN_H);
    this.mobP = new Uint8Array(SCREEN_W * SCREEN_H);
    this.r = new Uint16Array(8);
    this.reset();
  }

  loadRom(buf) {
    // CC3 ".rom" format: 'A8', segment count, its complement, then for each
    // segment first and last+1 page and big-endian words with a CRC.
    const b = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
    if (b[0] !== 0xA8) throw new Error('not a .rom image');
    const n = b[1];
    let p = 3;
    this.segments = [];
    for (let s = 0; s < n; s++) {
      const lo = b[p] << 8, hi = (b[p + 1] << 8) + 0x100; p += 2;
      for (let a = lo; a < hi; a++, p += 2) this.mem[a] = (b[p] << 8) | b[p + 1];
      p += 2; // CRC
      this.segments.push([lo, hi]);
    }
    this.reset();
  }

  reset() {
    let x = this.rngSeed || 1;
    const rnd = () => { x ^= x << 13; x ^= x >>> 17; x ^= x << 5; return x & 0xFFFF; };
    for (let a = 0x100; a < 0x1F0; a++) this.mem[a] = rnd() & 0xFF;
    for (let a = 0x200; a < 0x360; a++) this.mem[a] = rnd();
    for (let a = 0x4000; a < 0x4800; a++) this.mem[a] = rnd() & 0xFF;
    this.gram.fill(0); this.stic.fill(0);
    this.psg[0].fill(0); this.psg[1].fill(0);
    this.r.fill(0);
    this.S = this.Z = this.O = this.C = 0;
    this.I = 0; this.D = 0;
    this.noInt = 0;
    this.intr = false;
    this.fgbg = false;
    this.en = 0;
    this.frame = 0;
    this.cycles = 0;
    this.frameCycles = 0;
    this.halted = false;
    this.r[7] = this.findMain();
  }

  // The cartridge header at $5000 holds the program start as two 10-bit pairs,
  // low then high, third entry. The Executive would jump there after its own title.
  findMain() {
    const m = this.mem;
    return (m[0x5004] & 0xFF) | ((m[0x5005] & 0xFF) << 8);
  }

  read(a) {
    a &= 0xFFFF;
    if (a < 0x40) {
      if (a === 0x21) this.fgbg = false;
      if (a >= 0x18 && a < 0x20) return 0x3C00;
      return this.stic[a];
    }
    if (a >= 0xF0 && a <= 0xFF) {
      if (a >= 0xFE) return 0xFF;
      return this.psg[1][a - 0xF0];
    }
    if (a >= 0x1F0 && a <= 0x1FF) {
      if (a >= 0x1FE) return (~this.pads[a - 0x1FE]) & 0xFF;
      return this.psg[0][a - 0x1F0];
    }
    if (a >= 0x3800 && a < 0x4000) return this.gram[a & 0x1FF];
    return this.mem[a];
  }

  write(a, v) {
    a &= 0xFFFF; v &= 0xFFFF;
    if (a < 0x40) {
      if (a === 0x20) this.en = 2;
      if (a === 0x21) this.fgbg = true;
      this.stic[a] = v;
      return;
    }
    if (a >= 0xF0 && a < 0xFE) this.setPsg(1, a - 0xF0, v);
    else if (a >= 0x100 && a < 0x1F0) this.mem[a] = v & 0xFF;
    else if (a >= 0x1F0 && a < 0x1FE) this.setPsg(0, a - 0x1F0, v);
    else if (a >= 0x200 && a < 0x360) this.mem[a] = v;
    else if (a >= 0x3800 && a < 0x4000) this.gram[a & 0x1FF] = v & 0xFF;
    else if (a >= 0x4000 && a < 0x4800) this.mem[a] = v & 0xFF;
  }

  setPsg(chip, reg, v) {
    v &= 0xFF;
    if (this.psg[chip][reg] === v && reg !== 10) return;
    this.psg[chip][reg] = v;
    if (this.onPsg) this.onPsg(chip, reg, v, this.frameCycles);
  }

  // --------------------------------------------------------------- flags
  getSWD() { const f = (this.S << 7) | (this.Z << 6) | (this.O << 5) | (this.C << 4); return f | (f << 8); }
  setSWD(v) { this.S = (v >> 7) & 1; this.Z = (v >> 6) & 1; this.O = (v >> 5) & 1; this.C = (v >> 4) & 1; }
  sz(v) { this.S = (v >> 15) & 1; this.Z = v === 0 ? 1 : 0; }

  add(a, b, c) {
    const t = a + b + c, v = t & 0xFFFF;
    this.C = t > 0xFFFF ? 1 : 0;
    this.O = (~(a ^ b) & (a ^ v) & 0x8000) ? 1 : 0;
    this.S = (v >> 15) & 1; this.Z = v === 0 ? 1 : 0;
    return v;
  }

  sub(a, b) { return this.add(a, (~b) & 0xFFFF, 1); }

  // --------------------------------------------------------------- one instruction
  step() {
    const r = this.r;
    const pc = r[7];

    // Stand-ins for the two Executive addresses the cartridge touches
    if (pc === 0x1014) {       // end of interrupt: registers back, in reverse order
      this.setSWD(this.pop());
      r[5] = this.pop(); r[4] = this.pop(); r[3] = this.pop();
      r[2] = this.pop(); r[1] = this.pop(); r[0] = this.pop();
      r[7] = this.pop();
      return 60;
    }

    const op = this.mem[pc] & 0x3FF;
    r[7] = (pc + 1) & 0xFFFF;
    const dbd = this.D;
    this.D = 0;
    this.noInt = 0;

    if (op < 0x040) return this.opLow(op);
    if (op < 0x080) return this.opShift(op);
    if (op < 0x200) {
      const s = (op >> 3) & 7, d = op & 7, group = op >> 6;
      switch (group) {
        case 2: { const v = r[s]; this.sz(v); r[d] = v; return (d >= 6) ? 7 : 6; }             // MOVR
        case 3: r[d] = this.add(r[d], r[s], 0); return (d >= 6) ? 7 : 6;                       // ADDR
        case 4: r[d] = this.sub(r[d], r[s]); return (d >= 6) ? 7 : 6;                          // SUBR
        case 5: this.sub(r[d], r[s]); return (d >= 6) ? 7 : 6;                                 // CMPR
        case 6: { const v = r[d] & r[s]; this.sz(v); r[d] = v; return (d >= 6) ? 7 : 6; }      // ANDR
        default: { const v = r[d] ^ r[s]; this.sz(v); r[d] = v; return (d >= 6) ? 7 : 6; }     // XORR
      }
    }
    if (op < 0x240) {           // branches
      const disp = this.mem[r[7]];
      r[7] = (r[7] + 1) & 0xFFFF;
      if (op & 0x10) return 7;   // external condition: never true here
      let t;
      const cc = op & 7;
      switch (cc) {
        case 0: t = 1; break;
        case 1: t = this.C; break;
        case 2: t = this.O; break;
        case 3: t = this.S ^ 1; break;
        case 4: t = this.Z; break;
        case 5: t = this.S ^ this.O; break;
        case 6: t = this.Z | (this.S ^ this.O); break;
        default: t = this.S ^ this.C; break;
      }
      if (op & 8) t ^= 1;
      if (!t) return 7;
      r[7] = (op & 0x20) ? (r[7] - disp - 1) & 0xFFFF : (r[7] + disp) & 0xFFFF;
      return 9;
    }

    // Memory instructions: oooooommmddd
    const kind = op >> 6, m = (op >> 3) & 7, d = op & 7;

    if (kind === 9) {           // MVO
      this.noInt = 1;
      if (m === 0) { const a = this.mem[r[7]]; r[7]++; this.write(a, r[d]); return 11; }
      if (m === 7) { this.write(r[7], r[d]); r[7]++; return 9; }
      if (m === 6) { this.write(r[6], r[d]); r[6]++; return 9; }
      const a = r[m];
      this.write(a, r[d]);
      if (m >= 4) r[m]++;
      return 9;
    }

    // Everything else reads a value first
    let v, cost;
    if (m === 0) {
      const a = this.mem[r[7]]; r[7]++;
      v = this.read(a); cost = 10;
    } else if (m === 7) {
      if (dbd) {
        const lo = this.read(r[7]) & 0xFF; r[7]++;
        const hi = this.read(r[7]) & 0xFF; r[7]++;
        v = lo | (hi << 8); cost = 10;
      } else { v = this.read(r[7]); r[7]++; cost = 8; }
    } else if (m === 6) {
      if (dbd) {
        r[6]--; const lo = this.read(r[6]) & 0xFF;
        r[6]--; const hi = this.read(r[6]) & 0xFF;
        v = lo | (hi << 8); cost = 14;
      } else { r[6]--; v = this.read(r[6]); cost = 11; }
    } else {
      if (dbd) {
        const lo = this.read(r[m]) & 0xFF; if (m >= 4) r[m]++;
        const hi = this.read(r[m]) & 0xFF; if (m >= 4) r[m]++;
        v = lo | (hi << 8); cost = 10;
      } else { v = this.read(r[m]); if (m >= 4) r[m]++; cost = 8; }
    }

    switch (kind) {
      case 10: r[d] = v; break;                                                 // MVI
      case 11: r[d] = this.add(r[d], v, 0); break;                              // ADD
      case 12: r[d] = this.sub(r[d], v); break;                                 // SUB
      case 13: this.sub(r[d], v); break;                                        // CMP
      case 14: { const x = r[d] & v; this.sz(x); r[d] = x; break; }             // AND
      default: { const x = r[d] ^ v; this.sz(x); r[d] = x; break; }             // XOR
    }
    return cost;
  }

  pop() { this.r[6]--; return this.read(this.r[6]); }
  push(v) { this.write(this.r[6], v); this.r[6]++; }

  opLow(op) {
    const r = this.r;
    if (op >= 0x008) {
      const d = op & 7;
      switch (op >> 3) {
        case 1: { const v = (r[d] + 1) & 0xFFFF; this.sz(v); r[d] = v; return 6; }    // INCR
        case 2: { const v = (r[d] - 1) & 0xFFFF; this.sz(v); r[d] = v; return 6; }    // DECR
        case 3: { const v = (~r[d]) & 0xFFFF; this.sz(v); r[d] = v; return 6; }       // COMR
        case 4: r[d] = this.add(0, (~r[d]) & 0xFFFF, 1); return 6;                    // NEGR
        case 5: r[d] = this.add(r[d], 0, this.C); return 6;                           // ADCR
        case 6:
          if (op <= 0x033) { r[op & 3] = this.getSWD(); return 6; }                   // GSWD
          return 6;                                                                   // NOP, SIN
        default: this.setSWD(r[d]); return 6;                                         // RSWD
      }
    }
    switch (op) {
      case 0: this.halted = true; r[7] = (r[7] - 1) & 0xFFFF; return 4;   // HLT
      case 1: this.D = 1; this.noInt = 1; return 4;                       // SDBD
      case 2: this.I = 1; this.noInt = 1; return 4;                       // EIS
      case 3: this.I = 0; this.noInt = 1; return 4;                       // DIS
      case 4: {                                                           // J family
        const w1 = this.mem[r[7]] & 0x3FF, w2 = this.mem[(r[7] + 1) & 0xFFFF] & 0x3FF;
        const target = ((w1 & 0xFC) << 8) | w2;
        const link = (w1 >> 8) & 3, ff = w1 & 3;
        const ret = (r[7] + 2) & 0xFFFF;
        if (link !== 3) r[4 + link] = ret;
        if (ff === 1) this.I = 1; else if (ff === 2) this.I = 0;
        r[7] = target;
        return 12;
      }
      case 5: this.noInt = 1; return 4;                                   // TCI
      case 6: this.C = 0; this.noInt = 1; return 4;                       // CLRC
      default: this.C = 1; this.noInt = 1; return 4;                      // SETC
    }
  }

  opShift(op) {
    const r = this.r, d = op & 3, two = (op >> 2) & 1, x = r[d];
    let v;
    this.noInt = 1;
    switch ((op >> 3) & 7) {
      case 0:                                     // SWAP
        v = two ? ((x & 0xFF) << 8) | (x & 0xFF) : ((x & 0xFF) << 8) | (x >> 8);
        break;
      case 1: v = (x << (two ? 2 : 1)) & 0xFFFF; this.sz(v); r[d] = v; return two ? 8 : 6;   // SLL
      case 2:                                     // RLC
        if (two) { v = ((x << 2) | (this.C << 1) | this.O) & 0xFFFF; this.C = x >> 15; this.O = (x >> 14) & 1; }
        else { v = ((x << 1) | this.C) & 0xFFFF; this.C = x >> 15; }
        this.sz(v); r[d] = v; return two ? 8 : 6;
      case 3:                                     // SLLC
        if (two) { v = (x << 2) & 0xFFFF; this.C = x >> 15; this.O = (x >> 14) & 1; }
        else { v = (x << 1) & 0xFFFF; this.C = x >> 15; }
        this.sz(v); r[d] = v; return two ? 8 : 6;
      case 4: v = x >> (two ? 2 : 1); break;      // SLR
      case 5: {                                   // SAR
        const s = (x << 16) >> 16;
        v = (s >> (two ? 2 : 1)) & 0xFFFF;
        break;
      }
      case 6:                                     // RRC
        if (two) { v = (x >> 2) | (this.C << 14) | (this.O << 15); this.O = (x >> 1) & 1; this.C = x & 1; }
        else { v = (x >> 1) | (this.C << 15); this.C = x & 1; }
        break;
      default: {                                  // SARC
        const s = (x << 16) >> 16;
        if (two) { v = (s >> 2) & 0xFFFF; this.O = (x >> 1) & 1; this.C = x & 1; }
        else { v = (s >> 1) & 0xFFFF; this.C = x & 1; }
      }
    }
    // Right shifts and SWAP take the sign flag from bit 7
    this.S = (v >> 7) & 1; this.Z = v === 0 ? 1 : 0;
    r[d] = v;
    return two ? 8 : 6;
  }

  takeInterrupt() {
    const r = this.r;
    this.intr = false;           // the chip asks once a frame; the CPU leaves its enable flag alone
    this.push(r[7]);
    this.push(r[0]); this.push(r[1]); this.push(r[2]);
    this.push(r[3]); this.push(r[4]); this.push(r[5]);
    this.push(this.getSWD());
    r[5] = 0x1014;
    r[7] = (this.mem[0x100] & 0xFF) | ((this.mem[0x101] & 0xFF) << 8);
    return 60;
  }

  run(cycles) {
    let left = cycles;
    while (left > 0) {
      if (this.intr && this.I && !this.noInt && !this.D) { const c = this.takeInterrupt(); left -= c; this.frameCycles += c; continue; }
      const c = this.step();
      left -= c; this.frameCycles += c;
    }
    return left;
  }

  // One video frame: the interrupt, the blanking time, the picture, the rest.
  runFrame() {
    this.frame++;
    this.frameCycles = 0;
    this.intr = true;
    this.run(CYCLES_VBLANK);
    this.intr = false;
    this.render();
    const on = this.en > 0;
    if (this.en > 0) this.en--;
    this.run(CYCLES_FRAME - CYCLES_VBLANK - (on ? CYCLES_STOLEN : 0));
  }

  // --------------------------------------------------------------- the picture
  cardRow(gramCard, card, row) {
    return gramCard ? this.gram[(card * 8 + row) & 0x1FF] : this.grom[(card * 8 + row) & 0x7FF];
  }

  render() {
    const W = SCREEN_W, H = SCREEN_H, pic = this.pic, fgm = this.fgm, st = this.stic;
    const border = st[0x2C] & 15;
    pic.fill(border);
    fgm.fill(0);
    if (this.en <= 0) { pic.fill(0); return; }

    // Background cards. The delay registers shake the whole picture, moving objects too.
    const hd = st[0x30] & 7, vd = (st[0x31] & 7) * 2, bm = st[0x32] & 3;
    const mem = this.mem;
    let csp = 0;
    const cs = [st[0x28] & 15, st[0x29] & 15, st[0x2A] & 15, st[0x2B] & 15];
    for (let row = 0; row < 12; row++) {
      for (let col = 0; col < 20; col++) {
        const w = mem[0x200 + row * 20 + col];
        let fg, bg, card, isGram = (w & 0x800) !== 0, squares = false;
        if (this.fgbg) {
          fg = w & 7;
          bg = ((w >> 9) & 0xB) | ((w >> 11) & 4);
          card = (w >> 3) & 0x3F;
        } else {
          if (w & 0x2000) csp = (csp + 1) & 3;
          bg = cs[csp];
          if ((w & 0x1800) === 0x1000) squares = true;
          fg = (w & 7) | ((w >> 9) & 8);
          card = (w >> 3) & 0xFF;
          if (isGram) card &= 0x3F;
        }
        const ox = 8 + hd + col * 8, oy = 16 + vd + row * 16;
        for (let y = 0; y < 8; y++) {
          if (oy + y * 2 + 1 >= H) continue;
          let bits = 0, sqA = 0;
          if (squares) {
            const q = (y < 4 ? 0 : 2);
            const a = (w >> (q * 3)) & 7, b = (w >> ((q + 1) * 3)) & 7;
            const ca = a === 7 ? bg : a, cb = b === 7 ? bg : b;
            for (let x = 0; x < 8 && ox + x < W; x++) {
              const c = x < 4 ? ca : cb, p = (oy + y * 2) * W + ox + x;
              pic[p] = c; pic[p + W] = c;
            }
            sqA = 1;
          } else bits = this.cardRow(isGram, card, y);
          if (sqA) continue;
          for (let x = 0; x < 8 && ox + x < W; x++) {
            const on = (bits >> (7 - x)) & 1, c = on ? fg : bg, p = (oy + y * 2) * W + ox + x;
            pic[p] = c; pic[p + W] = c;
            fgm[p] = on; fgm[p + W] = on;
          }
        }
      }
    }

    // Moving objects: highest number first, so low numbers end up on top
    const mobC = this.mobC, mobP = this.mobP;
    mobC.fill(-1);
    for (let n = 7; n >= 0; n--) {
      const X = st[n], Y = st[8 + n], A = st[16 + n];
      if (!(X & 0x200) || (X & 0xFF) === 0) continue;
      const fg = (A & 7) | ((A >> 9) & 8);
      const pri = (A >> 13) & 1;
      const isGram = (A & 0x800) !== 0;
      let card = (A >> 3) & 0xFF;
      if (isGram) card &= 0x3F;
      const tall = (Y & 0x80) !== 0;
      if (tall) card &= 0xFE;
      const rows = tall ? 16 : 8;
      const rowH = 1 << ((Y >> 8) & 3);
      const wide = (X & 0x400) ? 2 : 1;
      const xflip = (Y & 0x400) !== 0, yflip = (Y & 0x800) !== 0;
      const x0 = (X & 0xFF) + hd, y0 = (Y & 0x7F) * 2 + vd;
      for (let row = 0; row < rows; row++) {
        const src = yflip ? rows - 1 - row : row;
        const bits = this.cardRow(isGram, card, src);
        if (!bits) continue;
        for (let k = 0; k < rowH; k++) {
          const yy = y0 + row * rowH + k;
          if (yy < 16 || yy >= H - 16) continue;
          for (let i = 0; i < 8; i++) {
            if (!((bits >> (xflip ? i : 7 - i)) & 1)) continue;
            for (let w = 0; w < wide; w++) {
              const xx = x0 + i * wide + w;
              if (xx < 8 || xx >= W - 8) continue;
              const p = yy * W + xx;
              mobC[p] = fg; mobP[p] = pri;
            }
          }
        }
      }
    }
    for (let p = 0; p < pic.length; p++) {
      const c = mobC[p];
      if (c < 0) continue;
      if (mobP[p] && fgm[p]) continue;
      pic[p] = c;
    }

    // The frame around the picture goes on last
    const left = 8 + hd + ((bm & 1) ? 8 : 0), top = 16 + vd + ((bm & 2) ? 16 : 0);
    for (let y = 0; y < H; y++) {
      const edge = y < top || y >= H - 16;
      for (let x = 0; x < W; x++) {
        if (edge || x < left || x >= W - 8) pic[y * W + x] = border;
      }
    }
  }

  // Text on the background cards, for tests
  screenText() {
    const lines = [];
    for (let row = 0; row < 12; row++) {
      let s = '';
      for (let col = 0; col < 20; col++) {
        const w = this.mem[0x200 + row * 20 + col];
        const card = this.fgbg ? (w >> 3) & 0x3F : (w >> 3) & 0xFF;
        s += (w & 0x800) || card >= 64 ? (card >= 64 && !(w & 0x800) ? '?' : '.') : String.fromCharCode(32 + card);
      }
      lines.push(s);
    }
    return lines.join('\n');
  }
}

if (typeof module !== 'undefined') module.exports = { Inty, PAD, INTY_PALETTE, SCREEN_W, SCREEN_H };
