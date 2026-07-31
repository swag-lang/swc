const SIZE = 524288;

const K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

let seed = 12345;
function rnd() {
    seed = (seed * 16807) % 2147483647;
    return seed;
}

// ---- data generation (not timed) ----
const msg = [];
for (let i = 0; i < SIZE; i++) msg.push(rnd() % 256);

// ---- timed work ----
const t0 = performance.now();

function rotr(x, k) {
    return ((x >>> k) | (x << (32 - k))) >>> 0;
}

const n = SIZE;
const totalBits = n * 8;
const buf = msg.slice();
buf.push(0x80);
while (buf.length % 64 !== 56) buf.push(0);
for (let s = 0; s < 8; s++) {
    buf.push(Math.floor(totalBits / Math.pow(2, 56 - 8 * s)) % 256);
}

let h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
let h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

const w = new Array(64).fill(0);
const nblocks = buf.length / 64;
for (let b = 0; b < nblocks; b++) {
    const o = b * 64;
    for (let t = 0; t < 16; t++) {
        const p = o + t * 4;
        w[t] = ((buf[p] << 24) | (buf[p + 1] << 16) | (buf[p + 2] << 8) | buf[p + 3]) >>> 0;
    }
    for (let t = 16; t < 64; t++) {
        const x = w[t - 15];
        const y = w[t - 2];
        const s0 = (rotr(x, 7) ^ rotr(x, 18) ^ (x >>> 3)) >>> 0;
        const s1 = (rotr(y, 17) ^ rotr(y, 19) ^ (y >>> 10)) >>> 0;
        w[t] = (w[t - 16] + s0 + w[t - 7] + s1) % 4294967296;
    }

    let a = h0, bb = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
    for (let t = 0; t < 64; t++) {
        const S1 = (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) >>> 0;
        const ch = ((e & f) ^ (~e & g)) >>> 0;
        const t1 = (h + S1 + ch + K[t] + w[t]) % 4294967296;
        const S0 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) >>> 0;
        const maj = ((a & bb) ^ (a & c) ^ (bb & c)) >>> 0;
        const t2 = (S0 + maj) % 4294967296;
        h = g;
        g = f;
        f = e;
        e = (d + t1) % 4294967296;
        d = c;
        c = bb;
        bb = a;
        a = (t1 + t2) % 4294967296;
    }

    h0 = (h0 + a) % 4294967296;
    h1 = (h1 + bb) % 4294967296;
    h2 = (h2 + c) % 4294967296;
    h3 = (h3 + d) % 4294967296;
    h4 = (h4 + e) % 4294967296;
    h5 = (h5 + f) % 4294967296;
    h6 = (h6 + g) % 4294967296;
    h7 = (h7 + h) % 4294967296;
}

const check = ((h0 ^ h1 ^ h2 ^ h3 ^ h4 ^ h5 ^ h6 ^ h7) >>> 0);

const t1 = performance.now();
console.log("CHECK=" + check + " MS=" + (t1 - t0).toFixed(3));
