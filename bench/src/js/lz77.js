const DATA_SIZE = 1 << 20;
const WORDS = 512;
const HASH_SIZE = 65536;
const WINDOW = 32768;
const MIN_MATCH = 4;
const MAX_MATCH = 258;
const MAX_CHAIN = 32;

let seed = 12345;
function rnd() {
    seed = (seed * 16807) % 2147483647;
    return seed;
}

// ---- data generation (not timed) ----
const letters = new Uint8Array(WORDS * 10);
const wordStart = new Array(WORDS);
const wordLen = new Array(WORDS);
let used = 0;
for (let k = 0; k < WORDS; k++) {
    const len = 2 + (rnd() % 8);
    wordStart[k] = used;
    wordLen[k] = len;
    for (let j = 0; j < len; j++) letters[used + j] = 97 + (rnd() % 26);
    used += len;
}

const n = DATA_SIZE;
const data = new Uint8Array(n);
let pos = 0;
while (pos < n) {
    const w = rnd() % WORDS;
    for (let j = 0; j < wordLen[w] && pos < n; j++) data[pos++] = letters[wordStart[w] + j];
    if (pos < n) data[pos++] = 32;
}

// ---- timed work ----
const t0 = performance.now();

function hashAt(d, p) {
    return (((d[p] * 33 + d[p + 1]) * 33 + d[p + 2]) * 33 + d[p + 3]) % HASH_SIZE;
}

const head = new Int32Array(HASH_SIZE).fill(-1);
const prev = new Int32Array(WINDOW).fill(-1);

const comp = new Uint8Array(n * 2 + 16);
let csize = 0;

let i = 0;
while (i + MIN_MATCH <= n) {
    let best = 0;
    let dist = 0;
    const limit = n - i < MAX_MATCH ? n - i : MAX_MATCH;
    const h = hashAt(data, i);
    let cand = head[h];
    let chain = 0;
    while (cand >= 0 && i - cand < WINDOW && chain < MAX_CHAIN) {
        let l = 0;
        while (l < limit && data[cand + l] === data[i + l]) l++;
        if (l > best) {
            best = l;
            dist = i - cand;
            if (l === limit) break;
        }
        cand = prev[cand % WINDOW];
        chain++;
    }

    prev[i % WINDOW] = head[h];
    head[h] = i;

    if (best >= MIN_MATCH) {
        comp[csize++] = 1;
        comp[csize++] = best - MIN_MATCH;
        comp[csize++] = (dist - 1) % 256;
        comp[csize++] = Math.floor((dist - 1) / 256);
        for (let p = i + 1; p < i + best; p++) {
            if (p + MIN_MATCH <= n) {
                const hp = hashAt(data, p);
                prev[p % WINDOW] = head[hp];
                head[hp] = p;
            }
        }
        i += best;
    } else {
        comp[csize++] = 0;
        comp[csize++] = data[i];
        i++;
    }
}

while (i < n) {
    comp[csize++] = 0;
    comp[csize++] = data[i];
    i++;
}

// ---- decompress and verify ----
const out = new Uint8Array(n);
let o = 0;
let c = 0;
while (c < csize) {
    if (comp[c] === 0) {
        out[o++] = comp[c + 1];
        c += 2;
    } else {
        const len = comp[c + 1] + MIN_MATCH;
        const back = comp[c + 2] + comp[c + 3] * 256 + 1;
        for (let k = 0; k < len; k++) {
            out[o] = out[o - back];
            o++;
        }
        c += 4;
    }
}

let same = o === n;
for (let k = 0; same && k < n; k++) {
    if (out[k] !== data[k]) same = false;
}

let hc = 0;
for (let k = 0; k < csize; k++) hc = (hc * 31 + comp[k]) % 1000003;

const check = same ? csize * 1000003 + hc : 0;

const t1 = performance.now();
console.log("CHECK=" + check + " MS=" + (t1 - t0).toFixed(3));
