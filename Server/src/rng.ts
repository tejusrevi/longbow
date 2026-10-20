// SplitMix64, bit for bit with Core/Sources/LongbowCore/Random/SplitMix64.swift.
// Nakama's JavaScript engine is not guaranteed to have BigInt, so 64-bit values
// are pairs of unsigned 32-bit halves and the maths is done in 16-bit pieces.

interface U64 { hi: number; lo: number }

function u64(hi: number, lo: number): U64 { return { hi: hi >>> 0, lo: lo >>> 0 }; }

function u64FromHex(hex: string): U64 {
  const h = hex.replace(/^0x/i, "");
  const padded = ("0000000000000000" + h).slice(-16);
  return u64(parseInt(padded.slice(0, 8), 16), parseInt(padded.slice(8), 16));
}

function u64FromInt(n: number): U64 { return u64(Math.floor(n / 4294967296), n % 4294967296); }

function add64(a: U64, b: U64): U64 {
  const lo = a.lo + b.lo;
  const carry = lo >= 4294967296 ? 1 : 0;
  return u64(a.hi + b.hi + carry, lo);
}

function xor64(a: U64, b: U64): U64 { return u64(a.hi ^ b.hi, a.lo ^ b.lo); }

function shr64(a: U64, n: number): U64 {
  if (n === 0) return a;
  if (n >= 32) return u64(0, a.hi >>> (n - 32));
  return u64(a.hi >>> n, ((a.lo >>> n) | (a.hi << (32 - n))) >>> 0);
}

// Low 64 bits of a × b, using 16-bit limbs so every partial product is exact.
function mul64(a: U64, b: U64): U64 {
  const a0 = a.lo & 0xffff, a1 = a.lo >>> 16, a2 = a.hi & 0xffff, a3 = a.hi >>> 16;
  const b0 = b.lo & 0xffff, b1 = b.lo >>> 16, b2 = b.hi & 0xffff, b3 = b.hi >>> 16;
  let c0 = a0 * b0;
  let c1 = (c0 >>> 16) + a0 * b1;
  let c2 = c1 >>> 16; c1 = (c1 & 0xffff) + a1 * b0; c2 += c1 >>> 16;
  c2 += a0 * b2; let c3 = Math.floor(c2 / 65536); c2 = (c2 & 0xffff) + a1 * b1;
  c3 += Math.floor(c2 / 65536); c2 = (c2 & 0xffff) + a2 * b0;
  c3 += Math.floor(c2 / 65536);
  c3 = (c3 + a0 * b3 + a1 * b2 + a2 * b1 + a3 * b0) & 0xffff;
  const lo = ((c1 & 0xffff) << 16 | (c0 & 0xffff)) >>> 0;
  const hi = ((c3 << 16) | (c2 & 0xffff)) >>> 0;
  return u64(hi, lo);
}

// a mod n for a small positive n (< 2^20).
function mod64(a: U64, n: number): number { return ((a.hi % n) * 4294967296 + a.lo) % n; }

const GOLDEN = u64(0x9E3779B9, 0x7F4A7C15);
const M1 = u64(0xBF58476D, 0x1CE4E5B9);
const M2 = u64(0x94D049BB, 0x133111EB);

function mix64(v: U64): U64 {
  let z = v;
  z = mul64(xor64(z, shr64(z, 30)), M1);
  z = mul64(xor64(z, shr64(z, 27)), M2);
  return xor64(z, shr64(z, 31));
}

/// Order-dependent hash of a seed and extra values (SplitMix64.hash).
function hash64(seed: U64, values: U64[]): U64 {
  let h = mix64(seed);
  for (let i = 0; i < values.length; i++) h = mix64(xor64(h, add64(values[i], GOLDEN)));
  return h;
}

class SplitMix64 {
  state: U64;
  constructor(seed: U64) { this.state = seed; }
  next(): U64 { this.state = add64(this.state, GOLDEN); return mix64(this.state); }
  /// Uniform in [0, 1) from the top 53 bits.
  nextUnit(): number {
    const v = shr64(this.next(), 11);
    return (v.hi * 4294967296 + v.lo) * 1.1102230246251565e-16; // 2^-53
  }
  /// Uniform integer in [lower, upper] (modulo, like the Swift version).
  nextInt(lower: number, upper: number): number { return lower + mod64(this.next(), upper - lower + 1); }
  nextDouble(lower: number, upper: number): number { return lower + (upper - lower) * this.nextUnit(); }
  nextBool(): boolean { return (this.next().lo & 1) === 1; }
}
