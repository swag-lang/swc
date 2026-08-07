const SIZE = 4194304; // 32-bit words, sixteen mebibytes of key stream

let seed = 12345;
function rnd() {
    seed = (seed * 16807) % 2147483647;
    return seed;
}

function rol(x, k) {
    return ((x << k) | (x >>> (32 - k))) >>> 0;
}

function quarterRound(s, a, b, c, d) {
    s[a] = (s[a] + s[b]) >>> 0;
    s[d] ^= s[a];
    s[d] = rol(s[d], 16);
    s[c] = (s[c] + s[d]) >>> 0;
    s[b] ^= s[c];
    s[b] = rol(s[b], 12);
    s[a] = (s[a] + s[b]) >>> 0;
    s[d] ^= s[a];
    s[d] = rol(s[d], 8);
    s[c] = (s[c] + s[d]) >>> 0;
    s[b] ^= s[c];
    s[b] = rol(s[b], 7);
}

// ---- data generation (not timed) ----
const data = new Uint32Array(SIZE);
for (let i = 0; i < SIZE; i++) data[i] = rnd() >>> 0;

const key = new Uint32Array(8);
for (let i = 0; i < 8; i++) key[i] = rnd() >>> 0;

const nonce = new Uint32Array(3);
for (let i = 0; i < 3; i++) nonce[i] = rnd() >>> 0;

// ---- timed work ----
const t0 = performance.now();

const initial = new Uint32Array(16);
initial[0] = 0x61707865;
initial[1] = 0x3320646E;
initial[2] = 0x79622D32;
initial[3] = 0x6B206574;
for (let i = 0; i < 8; i++) initial[4 + i] = key[i];
for (let i = 0; i < 3; i++) initial[13 + i] = nonce[i];

const state = new Uint32Array(16);
let offset = 0;
let counter = 1;
while (offset < SIZE) {
    initial[12] = counter >>> 0;

    for (let i = 0; i < 16; i++) state[i] = initial[i];

    for (let r = 0; r < 10; r++) {
        quarterRound(state, 0, 4, 8, 12);
        quarterRound(state, 1, 5, 9, 13);
        quarterRound(state, 2, 6, 10, 14);
        quarterRound(state, 3, 7, 11, 15);
        quarterRound(state, 0, 5, 10, 15);
        quarterRound(state, 1, 6, 11, 12);
        quarterRound(state, 2, 7, 8, 13);
        quarterRound(state, 3, 4, 9, 14);
    }

    for (let i = 0; i < 16; i++) data[offset + i] ^= (state[i] + initial[i]) >>> 0;

    offset += 16;
    counter = (counter + 1) >>> 0;
}

let check = 0;
for (let i = 0; i < SIZE; i++) check ^= ((data[i] + i) % 4294967296) >>> 0;
check = check >>> 0;

const t1 = performance.now();
console.log("CHECK=" + check + " MS=" + (t1 - t0).toFixed(3));
